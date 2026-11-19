module Merchants
  # Rules-only narration -> counterparty resolution.
  #
  #   resolver = Merchants::Resolver.new(household: household)
  #   result = resolver.resolve("WDL TFR UPI/DR/4123/NETFLIX/YESB/netflix@ybl/Mandate ...")
  #   result.merchant  # => #<Merchant slug: "netflix">
  #   result.label     # => "netflix" | "person" | "bank" | "cash" | "abstain"
  #
  # In order of strength: an exact UPI ID; a payee name (exact, or a
  # catalogue name that starts the payee, or a payee truncated from a
  # catalogue name); the local part of a UPI ID; a pg_trgm similarity match
  # that clearly beats every other merchant. Two signals that disagree mean
  # the resolver abstains rather than guesses: abstentions go to review (and,
  # from slice 5, to the LLM resolver).
  class Resolver
    Result = Data.define(:merchant, :counterparty, :via, :evidence) do
      def abstained? = via == "abstained"
      def label = merchant&.slug || counterparty || "abstain"
    end

    Hit = Data.define(:merchant_id, :via, :evidence, :strength)

    PREFIX_MIN = 5      # a catalogue name this long may match the start of a longer payee
    TRUNCATED_MIN = 6   # a payee this long may be a truncated catalogue name
    TRIGRAM_MIN = 0.5   # pg_trgm similarity needed for a fuzzy match...
    TRIGRAM_MARGIN = 0.15 # ...and how far it must beat the best other merchant

    # UPI IDs issued to merchants: QR codes, payment gateways, shop names.
    MERCHANT_VPA = /\A(q\d{5,}|paytmqr|gpay-|bharatpe|bpe|mab\.|pos\.|vyapar|.*(\.rzp|\.payu|razorpay|billdesk|cashfree|
      store|shop|mart|traders|pay\z|pay@))|@(okbiz|fbpe|pinelabs|hdfcbankjd|ikwik|yespay|axb\z)/x
    PHONE = /\A(91)?[6-9]\d{9}\z/
    # Handles of consumer UPI apps (bank handles like @icici serve merchants too).
    PERSONAL_PSP = /\A(ok(sbi|axis|hdfcbank|icici)|ybl|ibl|axl|paytm|pt(yes|axis|hdfc|sbi)|apl|yapl|upi|naviaxis|superyes|
      kotak811|jupiteraxis|fam|slc|wa(axis|hdfcbank|sbi|icici))\z/x
    BUSINESS = /STORE|TRADER|TRADING|ENTERPRISE|MART|MEDIC|PHARMA|CHEMIST|KIRANA|GENERAL|PVT|PRIVATE|LTD|LIMITED|LLP|
      INDIA|SERVICE|SOLUTION|TECHNO|FOOD|CAFE|HOTEL|RESTAURANT|DHABA|SWEET|BAKER|FRUIT|VEGETABLE|AGENC|CENTRE|CENTER|
      SHOP|SUPER|BAZAAR|BAZAR|ELECTRIC|MOBILE|PETROL|FUEL|AUTOMOBILE|MOTORS|GARAGE|CLINIC|HOSPITAL|DIAGNOS|LABS|
      LABORATOR|SALON|PARLOUR|TAILOR|TRAVELS|TOURS|CABS|EXPORT|IMPORT|INDUSTR|BROTHERS|ANDSONS|COMPANY|CORP|ASSOCIATE|
      INFOTECH|DIGITAL|PAYMENT|ONLINE|RETAIL|WHOLESALE|DAIRY|COFFEE|JEWEL|FOOTWEAR|FASHION|GARMENT|TEXTILE|HARDWARE|
      PAINT|BOOK|STATIONER|OPTIC|DENTAL|SCHOOL|ACADEMY|CLASSES|GYM|FITNESS|BANK|FINANCE|INSURANCE|SECURITIES|CAPITAL|
      SOCIETY|TRUST|FOUNDATION|MAHAL|BHANDAR|STALL|POINT|WORLD|ZONE|COLLECTION|EMPORIUM|PALACE|BOUTIQUE|
      SALES|RECHARGE|PARKING|SPORTS|CLOUD|STORAGE|POWER|SYSTEMS|MEDIA|NETWORK|STUDIO|LEARNING|HEALTH|CARE|GROUP/x
    # Card, NACH and bill-pay boilerplate before the merchant descriptor.
    DESCRIPTOR_START = /\A.*(?:\d{4,6}X{4,}\d{4}|ACH\s*DR\s*INW|ACHDR|NACH-?DR-?|NACH|ECS\s*DR|BILLPAY|BILL\s*PAY|BBPS|OTHPG|POS)[\s*\/\-]*/i

    def initialize(household: nil)
      @household = household
      @names = {}
      @vpas = {}
      @vpa_locals = Hash.new { |hash, key| hash[key] = Set.new }
      # Catalogue first so a household's own aliases override it.
      MerchantAlias.for_household(household).order(Arel.sql("household_id IS NOT NULL"))
        .pluck(:kind, :pattern, :merchant_id).each do |kind, pattern, merchant_id|
          if kind == "name" then @names[pattern] = merchant_id
          else
            @vpas[pattern] = merchant_id
            @vpa_locals[pattern.split("@").first] << merchant_id
          end
        end
      @merchants = Merchant.where(id: (@names.values + @vpas.values).uniq).index_by(&:id)
    end

    def resolve(narration, amount_paise: nil)
      parsed = Narration.parse(narration)
      case parsed.channel
      when :cash then counterparty("cash", "cash withdrawal or deposit")
      when :bank then counterparty("bank", "bank interest, fee or charge")
      when :upi then upi(parsed)
      when :neft, :imps then transfer(parsed)
      else descriptor(parsed)
      end
    end

    # Resolves and saves each transaction (e.g. after an import, or to
    # re-run the rules after the catalogue changes).
    def resolve_all!(bank_transactions)
      bank_transactions.each do |txn|
        txn.apply_resolution(resolve(txn.narration, amount_paise: txn.amount_paise))
        txn.save!
      end
    end

    private
      def upi(parsed)
        if parsed.vpa && (id = @vpas[parsed.vpa])
          return merchant(Hit.new(id, "vpa_alias", "UPI ID #{parsed.vpa}", 3))
        end

        name = name_hit(parsed.payee_key, "payee")
        local = vpa_local_hit(parsed.vpa_local)
        return abstain("payee and UPI ID point to different merchants") if name && local && name.merchant_id != local.merchant_id
        return merchant(name || local) if name || local

        if (fuzzy = trigram_hit(parsed.payee_key))
          return merchant(fuzzy)
        end
        return counterparty("person", "UPI ID and payee name look like an individual's") if upi_person?(parsed)

        abstain("no catalogue match for UPI payee #{parsed.payee.to_s.squish.inspect}")
      end

      def transfer(parsed)
        key = parsed.payee_key
        hit = name_hit(key, "beneficiary") || trigram_hit(key)
        return merchant(hit) if hit
        return counterparty("person", "#{parsed.channel.upcase} transfer to an individual") if personal_name?(parsed.payee)

        abstain("no catalogue match for #{parsed.channel.upcase} beneficiary")
      end

      # Card, NACH, bill-pay and anything else: look for a catalogue name
      # starting at any word of the narration, longest match first.
      def descriptor(parsed)
        tokens = parsed.text.upcase.split(/[\s*\/\-.,:#_()]+/).reject(&:empty?)
        hits = tokens.each_index.filter_map { |start| token_hit(tokens, start) }
        best = hits.max_by(&:strength)
        if best
          rivals = hits.select { |hit| hit.strength == best.strength && hit.merchant_id != best.merchant_id }
          return abstain("narration matches more than one merchant equally well") if rivals.any?
          return merchant(best)
        end

        name = descriptor_name(parsed.text)
        if (fuzzy = trigram_hit(Text.key(name)))
          return merchant(fuzzy)
        end
        abstain("no catalogue match in #{parsed.channel} narration")
      end

      def token_hit(tokens, start)
        suffix = Text.key(tokens[start..].join)
        # Short names (LIC, OLA, JIO) only as whole words; longer ones also as
        # the start of a longer word run ("NETFLIX" in "NETFLIXCOMMUMBAI").
        exact = (start...[ start + 6, tokens.size ].min).filter_map do |stop|
          key = Text.key(tokens[start..stop].join)
          key if @names.key?(key)
        end
        prefixed = @names.keys.select { |key| key.length >= PREFIX_MIN && suffix.start_with?(key) }
        key = (exact + prefixed).max_by(&:length)
        Hit.new(@names[key], "name_alias", "catalogue name #{key}", key.length) if key
      end

      def descriptor_name(text)
        rest = text.sub(DESCRIPTOR_START, "")
        rest.split(/\s+/).take_while { |word| word.count("0-9") < 4 }.join(" ")
      end

      def name_hit(key, what)
        return if key.blank?
        if (id = @names[key])
          return Hit.new(id, "name_alias", "#{what} #{key} is a catalogue name", 2)
        end

        prefix = @names.keys.select { |name| name.length >= PREFIX_MIN && key.start_with?(name) }.max_by(&:length)
        return Hit.new(@names[prefix], "name_alias", "#{what} starts with catalogue name #{prefix}", 2) if prefix

        return if key.length < TRUNCATED_MIN
        ids = @names.select { |name, _| name.start_with?(key) }.values.uniq
        Hit.new(ids.first, "name_alias", "#{what} #{key} is a truncated catalogue name", 1) if ids.one?
      end

      # SBI cuts long UPI IDs, often before the "@": match the part before
      # the "@" against the catalogue's UPI IDs (exactly, or as a truncation).
      def vpa_local_hit(local)
        return if local.blank? || local.length < 4
        ids = @vpa_locals.fetch(local, Set.new)
        if ids.empty? && local.length >= TRUNCATED_MIN
          ids = @vpa_locals.select { |known, _| known.start_with?(local) || (known.length >= TRUNCATED_MIN && local.start_with?(known)) }
            .values.reduce(Set.new, :|)
        end
        Hit.new(ids.first, "vpa_alias", "UPI ID starts #{local}", 1) if ids.one?
      end

      def trigram_hit(key)
        return if key.blank? || key.length < PREFIX_MIN

        rows = MerchantAlias.for_household(@household).kind_name.where("pattern % ?", key)
          .group(:merchant_id).order(Arel.sql("2 DESC")).limit(2)
          .pluck(:merchant_id, Arel.sql(MerchantAlias.sanitize_sql_array([ "max(similarity(pattern, ?))", key ])))
        (best_id, best), (_, second) = rows
        return if best.nil? || best < TRIGRAM_MIN || (second && best - second < TRIGRAM_MARGIN)

        Hit.new(best_id, "trigram", format("%s resembles a catalogue name (similarity %.2f)", key, best), 0)
      end

      def personal_name?(payee)
        key = Text.key(payee)
        key.match?(/\A[A-Z]{4,26}\z/) && !key.match?(BUSINESS)
      end

      # Small shops also have plain names, so a person needs a personal UPI
      # ID too: a phone number, or a consumer-app ID that shares four letters
      # in a row with the name (payees are compared space-free, see Narration).
      def upi_person?(parsed)
        vpa = (parsed.vpa || parsed.vpa_local).to_s
        local, domain = vpa.split("@")
        return false if local.blank? || vpa.match?(MERCHANT_VPA) || !personal_name?(parsed.payee)
        return true if local.match?(PHONE)

        letters = local.delete("^a-z")
        domain.to_s.match?(PERSONAL_PSP) && parsed.payee_key.downcase.chars.each_cons(4).any? { |run| letters.include?(run.join) }
      end

      def merchant(hit)
        Result.new(@merchants.fetch(hit.merchant_id), "merchant", hit.via, hit.evidence)
      end

      def counterparty(kind, evidence) = Result.new(nil, kind, "rule", evidence)
      def abstain(evidence) = Result.new(nil, nil, "abstained", evidence)
  end
end
