require "json"

module Synthetic
  # Generates labelled, entirely fabricated SBI-style narrations for the
  # merchant-resolution eval:
  #
  #   Synthetic::Narrations.new(seed: 7).examples(500)
  #   # => [#<Example id="s7-0001" narration="WDL TFR UPI/DR/..." amount_paise=-64900 label="netflix" ...>, ...]
  #
  # Labels are a catalogue slug (config/merchants.yml), "unknown" (a real
  # business that isn't in the catalogue), "person", "bank" or "cash".
  #
  # The surface forms below are written independently of the catalogue and
  # deliberately include forms it does not list (legal names, aggregator
  # UPI IDs, abbreviations), plus the damage real statements do: truncated
  # payee names and UPI IDs, mixed case and the fixed-width wrap that puts
  # spaces inside words. A resolver that only memorised the catalogue
  # should not score perfectly here.
  class Narrations
    Example = Data.define(:id, :narration, :amount_paise, :label, :channel, :noise) do
      def to_json(*) = to_h.to_json(*)
    end

    WRAP = 37 # statement detail column width (see spec/support/synthetic_sbi.rb)

    # slug => surface forms. upi: [payee as printed, UPI ID].
    MERCHANTS = {
      "netflix" => { upi: [ [ "NETFLIX", "netflixupi.payu@hdfcbank" ], [ "Netflix Entertainment Services", "netflix@icici" ],
                            [ "NETFLIX COM", "netflix.rzp@axisbank" ] ],
                     card: [ "NETFLIX.COM", "NETFLIX COM MUMBAI", "PAYU*NETFLIX" ], amounts: [ 149_00, 199_00, 499_00, 649_00 ] },
      "amazon_prime" => { upi: [ [ "AMAZON PRIME", "amazonprime@apl" ], [ "Prime Video", "primevideo@apl" ] ],
                          card: [ "AMAZON PRIME MEMBERSHIP", "PRIMEVIDEO.COM" ], amounts: [ 299_00, 599_00, 1_499_00 ] },
      "amazon" => { upi: [ [ "AMAZON PAY", "amazon@apl" ], [ "Amazon Seller Services", "amazonpay@apl" ],
                           [ "AMAZON INDIA", "amazon.seller@axisbank" ] ],
                    card: [ "WWW.AMAZON.IN", "AMAZON PAY INDIA PVT" ], amounts: 99_00..9_999_00 },
      "jiohotstar" => { upi: [ [ "JIOHOTSTAR", "jiohotstar@axisbank" ], [ "NOVI DIGITAL ENTERTAINMENT", "hotstar@icici" ],
                               [ "Star India Pvt Ltd", "starindia.payu@hdfcbank" ] ],
                        card: [ "HOTSTAR SUBSCRIPTION", "JIOHOTSTAR MUMBAI" ], amounts: [ 149_00, 299_00, 499_00, 1_499_00 ] },
      "sonyliv" => { upi: [ [ "SONY LIV", "sonyliv@hdfcbank" ], [ "CULVER MAX ENTERTAINMENT", "culvermax@icici" ] ],
                     card: [ "SONYLIV.COM" ], amounts: [ 399_00, 699_00, 1_499_00 ] },
      "spotify" => { upi: [ [ "SPOTIFY INDIA", "spotify@axisbank" ], [ "Spotify", "spotify.in@ybl" ] ],
                     card: [ "SPOTIFY INDIA", "PAYPAL *SPOTIFY", "SPOTIFY P1A2B3C4D5" ], amounts: [ 59_00, 119_00, 149_00, 179_00 ] },
      "youtube_premium" => { upi: [ [ "YOUTUBE PREMIUM", "youtube@axisbank" ], [ "GOOGLE YOUTUBE", "youtubepremium@okaxis" ] ],
                             card: [ "GOOGLE *YOUTUBE PREMIUM", "YOUTUBEPREMIUM G.CO/HELPPAY" ], amounts: [ 129_00, 149_00, 189_00 ] },
      "google_play" => { upi: [ [ "GOOGLE PLAY", "playstore@axisbank" ], [ "Google India Digital Services", "googleplay@axisbank" ] ],
                         card: [ "GOOGLE PLAY APPS", "GOOGLE *PLAY STORE" ], amounts: [ 10_00, 49_00, 99_00, 299_00 ] },
      "google_one" => { upi: [ [ "GOOGLE ONE", "googleone@axisbank" ] ],
                        card: [ "GOOGLE *GOOGLE ONE", "GOOGLE STORAGE G.CO" ], amounts: [ 35_00, 130_00, 210_00, 650_00 ] },
      "apple" => { upi: [ [ "APPLE MEDIA SERVICES", "appleservices.bdsk@hdfcbank" ] ],
                   card: [ "APPLE.COM/BILL", "APPLE SERVICES CORK", "ITUNES.COM/BILL" ], amounts: [ 99_00, 179_00, 195_00, 749_00 ] },
      "microsoft" => { card: [ "MICROSOFT*365 SUBSCR", "MSFT *MICROSOFT 365", "MICROSOFT INDIA" ], amounts: [ 489_00, 619_00 ] },
      "adobe" => { card: [ "ADOBE *CREATIVE CLOUD", "ADOBE SYSTEMS SOFTWARE" ], amounts: [ 1_675_00, 4_230_00 ] },
      "openai" => { card: [ "OPENAI *CHATGPT SUBSCR SAN FRANCISCO USD 20.00", "OPENAI CHATGPT", "CHATGPT SUBSCRIPTION" ],
                    amounts: [ 1_699_00, 1_740_00, 1_999_00 ] },
      "swiggy" => { upi: [ [ "SWIGGY", "swiggy@icici" ], [ "Bundl Technologies Pvt Ltd", "swiggyupi@axb" ],
                           [ "SWIGGY LIMITED", "swiggy.stores@icici" ], [ "SWIGGY INSTAMART", "instamart@icici" ] ],
                    card: [ "SWIGGY BANGALORE" ], amounts: 89_00..1_800_00 },
      "zomato" => { upi: [ [ "ZOMATO", "zomato@hdfcbank" ], [ "Zomato Limited", "zomatoorder@icici" ], [ "ETERNAL LIMITED", "zomato.payu@hdfcbank" ] ],
                    card: [ "ZOMATO ONLINE ORDER", "ZOMATO GURGAON" ], amounts: 99_00..2_200_00 },
      "blinkit" => { upi: [ [ "BLINKIT", "blinkit@hdfcbank" ], [ "Blink Commerce Pvt Ltd", "blinkit.payu@hdfcbank" ] ],
                     amounts: 99_00..2_500_00 },
      "zepto" => { upi: [ [ "ZEPTO", "zeptonow@axisbank" ], [ "KiranaKart Technologies", "zepto.rzp@icici" ] ], amounts: 99_00..2_000_00 },
      "bigbasket" => { upi: [ [ "BIGBASKET", "bigbasket@icici" ], [ "Supermarket Grocery Supplies", "bbnow@icici" ] ],
                       amounts: 199_00..4_000_00 },
      "dmart" => { upi: [ [ "AVENUE SUPERMARTS LTD", "dmart@hdfcbank" ], [ "DMART READY", "dmartready@ybl" ] ],
                   card: [ "DMART AVENUE SUPERMARTS" ], amounts: 150_00..6_000_00 },
      "flipkart" => { upi: [ [ "FLIPKART", "flipkart@axisbank" ], [ "Flipkart Internet Pvt Ltd", "fkrt@ybl" ] ],
                      card: [ "FLIPKART INTERNET", "WWW.FLIPKART.COM" ], amounts: 199_00..15_000_00 },
      "uber" => { upi: [ [ "UBER INDIA SYSTEMS", "uberindia@hdfcbank" ], [ "UBER", "uber.rides@icici" ] ],
                  card: [ "UBER *TRIP HELP.UBER.COM", "UBER INDIA" ], amounts: 60_00..900_00 },
      "ola" => { upi: [ [ "ANI TECHNOLOGIES PVT LTD", "olacabs@icici" ], [ "OLA", "olamoney@ybl" ] ], amounts: 60_00..800_00 },
      "irctc" => { upi: [ [ "IRCTC", "irctc@sbi" ], [ "Indian Railway Catering", "irctc.uts@sbi" ] ],
                   card: [ "IRCTC ETICKETING", "WWW IRCTC CO IN" ], amounts: 120_00..4_500_00 },
      "indian_oil" => { upi: [ [ "INDIAN OIL CORPORATION", "iocl@sbi" ] ], card: [ "IOCL COCO OUTLET", "INDIANOIL FUEL STN" ],
                        amounts: 300_00..3_000_00 },
      "jio" => { upi: [ [ "RELIANCE JIO INFOCOMM", "jiomobility@hdfcbank" ], [ "JIO", "myjio@sbi" ] ], bill: [ "JIO PREPAID", "RELIANCE JIO" ],
                 amounts: [ 199_00, 249_00, 299_00, 349_00, 799_00 ] },
      "airtel" => { upi: [ [ "BHARTI AIRTEL", "airtel.payu@axisbank" ], [ "AIRTEL", "airtelpostpaid@icici" ] ],
                    bill: [ "AIRTEL POSTPAID", "BHARTI AIRTEL LTD" ], amounts: [ 299_00, 399_00, 449_00, 599_00 ] },
      "act_fibernet" => { upi: [ [ "ACT FIBERNET", "actfibernet@icici" ] ], bill: [ "ATRIA CONVERGENCE TECH", "ACT FIBERNET" ],
                          amounts: [ 799_00, 999_00, 1_199_00 ] },
      "tata_play" => { upi: [ [ "TATA PLAY", "tataplay@hdfcbank" ] ], bill: [ "TATA PLAY DTH", "TATA SKY" ], amounts: [ 250_00, 350_00, 480_00 ] },
      "msedcl" => { upi: [ [ "MSEDCL", "msedcl@sbi" ], [ "BILLDESK", "msedcl.billdesk@hdfcbank" ] ],
                    bill: [ "MSEDCL", "MAHAVITARAN", "MAHARASHTRA STATE ELEC DIST" ], amounts: 400_00..4_000_00 },
      "tata_power" => { upi: [ [ "TATA POWER", "tatapower@hdfcbank" ] ], bill: [ "TATA POWER CO LTD MUMBAI", "TATA POWER-DDL" ],
                        amounts: 500_00..5_000_00 },
      "adani_electricity" => { upi: [ [ "ADANI ELECTRICITY MUMBAI", "adanielectricity@icici" ] ], bill: [ "ADANI ELECTRICITY", "AEML" ],
                               amounts: 500_00..5_000_00 },
      "mahanagar_gas" => { upi: [ [ "MAHANAGAR GAS LTD", "mgl@icici" ] ], bill: [ "MAHANAGAR GAS", "MGL PNG BILL" ], amounts: 300_00..1_500_00 },
      "lic" => { nach: [ "LIC OF INDIA", "LICI PREMIUM", "LIFE INSURANCE CORPN" ], upi: [ [ "LIC", "licpremium@sbi" ] ],
                 amounts: [ 2_356_00, 4_712_00, 10_250_00 ] },
      "hdfc_life" => { nach: [ "HDFC LIFE INSURANCE CO", "HDFC STANDARD LIFE" ], amounts: [ 3_000_00, 5_000_00, 12_500_00 ] },
      "icici_prulife" => { nach: [ "ICICI PRUDENTIAL LIFE INS", "ICICIPRU LIFE" ], amounts: [ 2_500_00, 6_000_00 ] },
      "star_health" => { nach: [ "STAR HEALTH AND ALLIED INS", "STAR HEALTH INSURANCE" ], amounts: [ 1_800_00, 2_400_00 ] },
      "iccl" => { nach: [ "INDIAN CLEARING CORP", "ICCL", "BSE STAR MF", "INDIAN CLEARING CORPORATION LTD" ],
                  amounts: [ 500_00, 1_000_00, 2_000_00, 5_000_00 ] },
      "hdfc_mf" => { nach: [ "HDFC MUTUAL FUND", "HDFC MF SIP" ], amounts: [ 1_000_00, 3_000_00 ] },
      "sbi_mf" => { nach: [ "SBI MUTUAL FUND", "SBI FUNDS MANAGEMENT" ], amounts: [ 500_00, 2_500_00 ] },
      "groww" => { upi: [ [ "GROWW", "groww@axisbank" ], [ "Nextbillion Technology", "groww.brk@validicici" ] ], amounts: [ 500_00, 1_000_00 ] },
      "zerodha" => { upi: [ [ "ZERODHA BROKING LTD", "zerodha@hdfcbank" ] ], amounts: [ 5_000_00, 10_000_00, 25_000_00 ] },
      "bajaj_finance" => { nach: [ "BAJAJ FINANCE LTD", "BAJAJ FIN LTD", "BAJAJ FINSERV" ], amounts: [ 1_850_00, 3_333_00, 4_999_00 ] },
      "cred" => { upi: [ [ "CRED", "cred.club@axisbank" ], [ "Dreamplug Technologies", "cred.rent@axisbank" ] ], amounts: 1_000_00..40_000_00 },
      "nobroker" => { upi: [ [ "NOBROKER TECHNOLOGIES", "nobroker@icici" ] ], amounts: [ 18_000_00, 22_000_00, 25_000_00 ] },
      "cultfit" => { upi: [ [ "CUREFIT HEALTHCARE", "cultfit@icici" ] ], card: [ "CULT.FIT BANGALORE" ], amounts: [ 999_00, 1_499_00 ] },
      "apollo_pharmacy" => { upi: [ [ "APOLLO PHARMACY", "apollopharmacy@hdfcbank" ], [ "Apollo Healthco Ltd", "apollo247@icici" ] ],
                             amounts: 80_00..2_500_00 },
      "times_prime" => { card: [ "TIMES PRIME MEMBERSHIP", "TIMES INTERNET LTD" ], amounts: [ 1_199_00 ] }
    }.freeze

    # Businesses that are not in the catalogue. Some are near-misses for
    # catalogue names (decoys for fuzzy matching).
    UNKNOWN_BUSINESSES = [
      "SHREE GANESH KIRANA STORES", "SAI MEDICAL AND GENERAL", "NEW BOMBAY TRADERS", "ANNAPURNA SWEETS",
      "KRISHNA FRUITS AND VEG", "LAXMI ELECTRONICS", "CAFE MOCHA BANDRA", "HOTEL SAI PALACE", "RAJ PETROLEUM",
      "PATEL BROTHERS", "MODERN BAKERY", "SURESH AUTO SERVICE", "OLA ELECTRIC SERVICE CENTRE", "STAR BAZAAR",
      "APOLLO TYRES SHOWROOM", "TATA CLIQ", "AMAZE FOOTWEAR", "JIO WORLD DRIVE PARKING", "NETAJI BOOK DEPOT",
      "GREEN LEAF DHABA", "SHIV SHAKTI HARDWARE", "BALAJI MOBILE POINT", "VIJAY SALES", "CROMA INFINITI RETAIL",
      "DECATHLON SPORTS INDIA", "MCDONALDS WESTLIFE", "STARBUCKS TATA", "CHAI POINT", "LENSKART SOLUTIONS",
      "NYKAA E RETAIL", "URBAN COMPANY", "PHONEPE RECHARGE", "SPENCERS RETAIL", "MORE RETAIL"
    ].freeze
    MERCHANT_VPAS = [
      ->(rng) { "paytmqr#{rng.rand(10**13..(10**14 - 1))}@paytm" }, ->(rng) { "q#{rng.rand(10**8..(10**9 - 1))}@ybl" },
      ->(rng) { "gpay-#{rng.rand(10**10..(10**11 - 1))}@okbizaxis" }, ->(rng) { "bharatpe.#{rng.rand(10**9..(10**10 - 1))}@fbpe" },
      ->(rng) { "mab.#{rng.rand(10**11..(10**12 - 1))}@axisbank" }
    ].freeze
    EMPLOYERS = [ "ACME TECHNOLOGIES PVT LTD", "SUNRISE INFOTECH SOLUTIONS", "BLUE OCEAN LOGISTICS LLP" ].freeze
    UNKNOWN_NACH = [ "TATA CAPITAL FIN SERV", "HOME CREDIT INDIA FIN", "ADITYA BIRLA SUN LIFE", "NIPPON INDIA MF" ].freeze

    FIRST = %w[ ANANYA ROHAN MEERA KABIR PRIYA ARJUN SNEHA VIKRAM POOJA RAHUL DIVYA AMIT NEHA SANJAY RITU KARAN
      SUNITA RAJESH DEEPA MANOJ KAVITA SURESH ANJALI NIKHIL ].freeze
    LAST = %w[ ROY DAS IYER SEN SHARMA PATEL REDDY NAIR GUPTA KULKARNI DESAI JOSHI MENON BOSE CHATTERJEE PILLAI
      MEHTA RAO SINGH VERMA GHOSH SHAH MISHRA ].freeze
    PERSONAL_PSPS = %w[ oksbi okaxis okhdfcbank okicici ybl ibl axl paytm upi ].freeze
    BANKS = %w[ YESB HDFC ICIC UTIB SBIN PUNB KKBK BARB IDIB ].freeze
    NOTES = [ "Payment fo", "UPI", "Mandate", "Pay to", "Sent from Paytm", "NA", "Payment from Ph", "Collect" ].freeze
    BRANCHES = %w[ BIDHANNAGAR ANDHERI KORAMANGALA SALTLAKE THANE BANDRA ].freeze

    # [channel, weight]
    MIX = { upi_merchant: 38, upi_gateway: 3, upi_unknown: 9, upi_person: 12, card: 9, nach: 7, bill: 5, refund: 3,
            transfer_person: 5, salary: 2, unknown_nach: 2, cash: 3, bank: 2 }.freeze
    # Payments where the statement shows only the payment gateway. The label
    # is the true merchant, which the narration alone cannot reveal: the
    # right answer is to abstain.
    GATEWAYS = [ [ "RAZORPAY", "razorpay" ], [ "PAYU", "payu" ], [ "CASHFREE", "cashfree" ], [ "PAYTM PAYMENTS", "paytm-pg" ] ].freeze

    def initialize(seed:)
      @seed = seed
      @rng = Random.new(seed)
    end

    def examples(count)
      Array.new(count) { |index| example(format("s%d-%04d", @seed, index + 1)) }
    end

    def self.write_jsonl(path, examples)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, examples.map(&:to_json).join("\n") + "\n")
    end

    private
      attr_reader :rng

      def example(id)
        channel = weighted(MIX)
        noise = []
        narration, amount, label = send(channel, noise)
        Example.new(id, wrap(narration), amount, label, channel.to_s, noise)
      end

      def upi_merchant(noise)
        slug, info = pick(MERCHANTS.select { |_, value| value[:upi] })
        payee, vpa = pick(info[:upi])
        amount = amount_for(info)
        if rng.rand < 0.05
          noise << "1 rupee mandate"
          amount = 100
        end
        [ upi_line("DR", damage_payee(payee, noise), damage_vpa(vpa, noise), noise), -amount, slug ]
      end

      def upi_gateway(noise)
        slug, info = pick(MERCHANTS.select { |_, value| value[:upi] })
        payee, handle = pick(GATEWAYS)
        noise << "gateway only"
        vpa = "#{handle}.#{rng.rand(10**6..(10**7 - 1))}@#{pick(%w[ icici hdfcbank axisbank yesbank ])}"
        [ upi_line("DR", payee, damage_vpa(vpa, noise), noise), -amount_for(info), slug ]
      end

      def refund(noise)
        slug, info = pick(MERCHANTS.select { |_, value| value[:upi] })
        payee, vpa = pick(info[:upi])
        noise << "refund"
        [ upi_line("CR", damage_payee(payee, noise), damage_vpa(vpa, noise), noise, note: "Refund"), amount_for(info) / 2 + 1, slug ]
      end

      def upi_unknown(noise)
        name = pick(UNKNOWN_BUSINESSES)
        vpa = rng.rand < 0.75 ? pick(MERCHANT_VPAS).call(rng) : "#{name.split.first.downcase}#{rng.rand(10..99)}@#{pick(PERSONAL_PSPS)}"
        [ upi_line("DR", damage_payee(name, noise), damage_vpa(vpa, noise), noise), -rng.rand(20_00..3_000_00), "unknown" ]
      end

      def upi_person(noise)
        first, last = pick(FIRST), pick(LAST)
        vpa = case rng.rand(3)
        when 0 then "#{rng.rand(6..9)}#{rng.rand(10**8..(10**9 - 1))}@#{pick(PERSONAL_PSPS)}"
        when 1 then "#{first.downcase}.#{last.downcase}@#{pick(PERSONAL_PSPS)}"
        else "#{first.downcase}#{rng.rand(1..999)}@#{pick(PERSONAL_PSPS)}"
        end
        direction = rng.rand < 0.4 ? "CR" : "DR"
        amount = rng.rand(100_00..25_000_00)
        [ upi_line(direction, damage_payee("#{first} #{last}", noise), damage_vpa(vpa, noise), noise),
          direction == "CR" ? amount : -amount, "person" ]
      end

      def card(noise)
        slug, info = pick(MERCHANTS.select { |_, value| value[:card] })
        mask = "#{pick(%w[ 459150 524193 607152 ])}XXXXXX#{rng.rand(1000..9999)}"
        prefix = pick([ "DEBIT CARD-OTHPG", "POS", "ECOM PUR", "BY DEBIT CARD-OTHPOS", "INTL POS TXN" ])
        [ "#{prefix} #{mask} #{pick(info[:card])}", -amount_for(info), slug ]
      end

      def nach(noise)
        slug, info = pick(MERCHANTS.select { |_, value| value[:nach] })
        [ nach_line(pick(info[:nach])), -amount_for(info), slug ]
      end

      def unknown_nach(noise)
        [ nach_line(pick(UNKNOWN_NACH)), -rng.rand(1_000_00..10_000_00), "unknown" ]
      end

      def bill(noise)
        slug, info = pick(MERCHANTS.select { |_, value| value[:bill] })
        biller = pick(info[:bill])
        consumer = rng.rand(10**9..(10**12 - 1))
        line = rng.rand < 0.5 ? "TO TRANSFER-INB BillPay #{biller} #{consumer}" : "BBPS/#{biller}/#{consumer}/#{rng.rand(10**6)}"
        [ line, -amount_for(info), slug ]
      end

      def transfer_person(noise)
        name = "#{pick(FIRST)} #{pick(LAST)}"
        case rng.rand(3)
        when 0 then [ "BY TRANSFER-NEFT*#{pick(BANKS)}0#{rng.rand(100_000..999_999)}*N#{rng.rand(10**11..(10**12 - 1))}*#{name}",
          rng.rand(1_000_00..50_000_00), "person" ]
        when 1 then [ "TO TRANSFER-IMPS/P2A/#{rng.rand(10**11..(10**12 - 1))}/#{name.delete(" ")}/#{pick(BANKS)}/X#{rng.rand(1000..9999)}",
          -rng.rand(500_00..30_000_00), "person" ]
        else
          noise << "internet banking transfer"
          [ "TO TRANSFER-INB #{name}", -rng.rand(500_00..30_000_00), "person" ]
        end
      end

      def salary(noise)
        [ "BY TRANSFER-NEFT*ICIC0000104*CMS#{rng.rand(10**9)}*#{pick(EMPLOYERS)}", rng.rand(40_000_00..150_000_00), "unknown" ]
      end

      def cash(noise)
        branch = pick(BRANCHES)
        case rng.rand(4)
        when 0 then [ "ATM WDL-ATM CASH #{rng.rand(100_000..999_999)} #{branch}", -rng.rand(5..100) * 100_00, "cash" ]
        when 1 then [ "CASH WITHDRAWAL-SELF", -rng.rand(5..100) * 100_00, "cash" ]
        when 2 then [ "CSH DEP (CDM) #{rng.rand(100_000..999_999)} #{branch}", rng.rand(5..100) * 100_00, "cash" ]
        else [ "CASH DEPOSIT-BY SELF", rng.rand(5..100) * 100_00, "cash" ]
        end
      end

      def bank(noise)
        pick([
          [ "CREDIT INTEREST", rng.rand(10_00..2_000_00), "bank" ],
          [ "INT.PD 01-04-2026 TO 30-09-2026", rng.rand(10_00..2_000_00), "bank" ],
          [ "SMS CHGS QTR ENDING SEP 2026", -rng.rand(15_00..20_00), "bank" ],
          [ "DEBIT CARD ANNUAL FEE + GST", -236_00, "bank" ],
          [ "ATM AMC CHGS", -147_50, "bank" ],
          [ "MIN BAL CHGS INCL GST", -rng.rand(50_00..600_00), "bank" ]
        ])
      end

      def upi_line(direction, payee, vpa, noise, note: pick(NOTES))
        ref = rng.rand(10**11..(10**12 - 1))
        body = "UPI/#{direction}/#{ref}/#{payee}/#{pick(BANKS)}/#{vpa}/#{note}"
        if rng.rand < 0.5
          "#{direction == "DR" ? "WDL TFR" : "DEP TFR"} #{body} 0097#{rng.rand(6..7)}#{rng.rand(10**8)} AT 09482 #{pick(BRANCHES)}"
        else
          "#{direction == "DR" ? "TO" : "BY"} TRANSFER-#{body}--"
        end
      end

      def nach_line(name)
        case rng.rand(3)
        when 0 then "ACH DR INW #{name} #{rng.rand(10**9..(10**10 - 1))}"
        when 1 then "DEBIT-ACHDr #{name} #{rng.rand(10**9..(10**10 - 1))}"
        else "NACH-DR-#{name}-#{rng.rand(10**9..(10**10 - 1))}"
        end
      end

      # Payee names get cut to a fixed width and are sometimes printed as
      # registered (mixed case).
      def damage_payee(payee, noise)
        payee = payee.upcase if rng.rand < 0.8
        if payee.length > 12 && rng.rand < 0.35
          noise << "payee truncated"
          payee = payee[0, rng.rand(8..12)].rstrip
        end
        payee
      end

      # Long UPI IDs lose their domain or get cut short.
      def damage_vpa(vpa, noise)
        roll = rng.rand
        if roll < 0.25
          noise << "UPI ID without domain"
          vpa.split("@").first
        elsif roll < 0.4
          noise << "UPI ID truncated"
          vpa[0, [ rng.rand(8..12), vpa.length ].min]
        else
          vpa
        end
      end

      # What the importer stores: the fixed-width detail column joined with
      # spaces, so long words are split (same rule as SyntheticSbi.wrap).
      def wrap(text)
        lines = [ +"" ]
        text.split(" ").each do |word|
          word.scan(/.{1,#{WRAP}}/).each do |piece|
            if lines.last.empty? then lines.last << piece
            elsif lines.last.length + 1 + piece.length <= WRAP then lines.last << " " << piece
            else lines << piece.dup
            end
          end
        end
        lines.join(" ")
      end

      def amount_for(info)
        amounts = info.fetch(:amounts)
        amounts.is_a?(Range) ? rng.rand(amounts) : pick(amounts)
      end

      def pick(list) = list.to_a.sample(random: rng)

      def weighted(weights)
        roll = rng.rand(weights.values.sum)
        weights.each { |key, weight| return key if (roll -= weight).negative? }
      end
  end
end
