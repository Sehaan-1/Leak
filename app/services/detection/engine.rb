module Detection
  # Finds recurring charges in a household's merchant transactions and what
  # is worth flagging about them:
  #
  #   result = Detection::Engine.new(as_of: Date.new(2026, 10, 31)).call(txns)  # txns: [Detection::Txn]
  #   result.series    # => [Series] every recurring series, commitments included
  #   result.findings  # => [Finding] subscription | price_increase | duplicate
  #
  # Pure Ruby over plain values, so the eval runs it on synthetic histories
  # without a database (Detection::Run persists it for a household).
  #
  # Per merchant, after dropping mandate set-ups (₹1 AutoPay debits) and
  # refunded charges, it chains charges that land where the cadence expects
  # them (allowing one missed period) at the same price, following small
  # drift (USD prices converted to rupees). A charge at the expected date at
  # a clearly different price, confirmed by another at the new price, is a
  # price step within the same series. Two series running at once at the
  # same merchant are a second subscription, not a price change. A chain
  # the merchant's other same-price charges could have formed by chance is
  # coincidence (the usual ride), and merchants where people mostly buy
  # things get stricter rules. Commitments (SIPs, EMIs, rent, insurance, utilities, card bills)
  # become series but are never flagged.
  class Engine
    Charge = Data.define(:id, :merchant, :category, :on, :amount_paise)

    Series = Data.define(:merchant, :category, :cadence, :levels, :status, :flagged, :next_expected_on) do
      def charges = levels.flatten
      def amount_paise = levels.last.last.amount_paise
      def monthly_cost_paise = Detection.monthly_cost(amount_paise, cadence.name)
      def first_charged_on = levels.first.first.on
      def last_charged_on = levels.last.last.on
      def active? = status == "active"

      # [old price, first charge at the new price] for each step up.
      def increases
        levels.each_cons(2).filter_map do |before, after|
          [ before.last.amount_paise, after.first ] if after.first.amount_paise > before.last.amount_paise
        end
      end
    end

    Finding = Data.define(:kind, :series, :amount_paise, :previous_amount_paise, :step_charge, :related) do
      def monthly_cost_paise = Detection.monthly_cost(amount_paise, series.cadence.name)
    end

    Result = Data.define(:series, :findings, :mandates, :refunded)

    # How strict to be at one merchant (see `noisy` in config/detection.yml).
    Rules = Data.define(:cadences, :drift, :min_charges, :tolerance, :skips, :steps) do
      def minimum(cadence) = [ cadence.min_charges, min_charges ].max
      def tolerance_for(cadence) = tolerance ? [ tolerance, cadence.tolerance ].min : cadence.tolerance
    end

    def initialize(as_of:, settings: Detection.config)
      @as_of = as_of
      @settings = settings
      @cadences = Detection.cadences(settings)
      @commitments = settings.fetch("commitment_categories")
    end

    def call(txns)
      txns = txns.reject { |txn| txn.merchant.nil? || txn.amount_paise.zero? }
      mandates, txns = txns.partition { |txn| txn.amount_paise.abs <= @settings.fetch("mandate_max_paise") }
      debits, credits = txns.partition { |txn| txn.amount_paise.negative? }
      refunded = refunded_ids(debits, credits)
      charges = debits.reject { |txn| refunded.include?(txn.id) }
        .map { |txn| Charge.new(txn.id, txn.merchant, txn.category, txn.on, -txn.amount_paise) }

      dates = txns.map(&:on)
      @span_days = dates.empty? ? 1 : [ (dates.max - dates.min).to_i + 1, 1 ].max
      series = charges.group_by(&:merchant).sort.flat_map { |_, list| series_for(list) }
      Result.new(series, findings(series), mandates.map(&:id), refunded.to_a)
    end

    private
      # A credit refunds the latest earlier debit at the same merchant for
      # exactly the same amount, within the refund window.
      def refunded_ids(debits, credits)
        window = @settings.fetch("refund_window_days")
        matched = Set.new
        credits.sort_by { |txn| [ txn.on, txn.id ] }.each do |credit|
          debit = debits.select do |txn|
            txn.merchant == credit.merchant && txn.amount_paise == -credit.amount_paise &&
              (credit.on - txn.on).between?(0, window) && !matched.include?(txn.id)
          end.max_by { |txn| [ txn.on, txn.id ] }
          matched << debit.id if debit
        end
        matched
      end

      def rules_for(charge)
        noisy = @settings.fetch("noisy")
        stores = @settings.fetch("app_stores")
        if noisy.fetch("categories").include?(charge.category)
          Rules.new(noisy.fetch("cadences").map { |name| @cadences.fetch(name) }, noisy.fetch("exact_drift"),
            noisy.fetch("min_charges"), noisy.fetch("tolerance"), 0, false)
        elsif stores.fetch("merchants").include?(charge.merchant)
          Rules.new(stores.fetch("cadences").map { |name| @cadences.fetch(name) }, stores.fetch("exact_drift"),
            stores.fetch("min_charges"), nil, 1, true)
        else
          Rules.new(@cadences.values, @settings.fetch("amount_drift"), 0, nil, 1, true)
        end
      end

      def series_for(charges)
        rules = rules_for(charges.first)
        remaining = charges.sort_by { |charge| [ charge.on, charge.id ] }
        found = []

        rules.cadences.each do |cadence|
          index = 0
          while index < remaining.size
            levels = chain(remaining[index], remaining, cadence, rules)
            if levels.sum(&:size) >= rules.minimum(cadence) && !coincidence?(levels, remaining, cadence, rules)
              found << build_series(charges.first, cadence, levels)
              taken = levels.flatten.to_set(&:id)
              remaining = remaining.reject { |charge| taken.include?(charge.id) }
            else
              index += 1
            end
          end
        end
        found
      end

      # Could the merchant's other charges at the same price have lined up
      # like this by chance (the usual ride, a fuel top-up, an in-app
      # purchase)? With λ the daily rate of same-price charges outside the
      # chain, a step landing in its tolerance window w by chance has
      # probability p = 1 - e^(-λw); the chain is coincidence if
      # seeds × Πp, the expected number of such chains, reaches
      # coincidence_alpha. No other charges at that price: never.
      def coincidence?(levels, pool, cadence, rules)
        chained = levels.flatten.to_set(&:id)
        others = levels.map do |level|
          pool.count { |charge| !chained.include?(charge.id) && same_price?(charge, level.first, rules.drift) }
        end
        return false if others.sum.zero?

        log_p = 0.0
        levels.zip(others).each do |level, count|
          rate = count.fdiv(@span_days)
          level.each_cons(2) do |before, after|
            periods = [ ((after.on - before.on) / cadence.period).round, 1 ].max
            p = 1 - Math.exp(-rate * (2 * rules.tolerance_for(cadence) * periods + 1))
            return false if p.zero?

            log_p += Math.log(p)
          end
        end
        (others.sum + chained.size) * Math.exp(log_p) >= @settings.fetch("coincidence_alpha")
      end

      def build_series(first, cadence, levels)
        last = levels.last.last
        status = (@as_of - last.on) <= cadence.offset + cadence.tolerance ? "active" : "ended"
        Series.new(first.merchant, first.category, cadence, levels, status, !@commitments.include?(first.category),
          last.on + cadence.offset)
      end

      # Price levels of the chain starting at seed: [[charge, ...], ...].
      def chain(seed, pool, cadence, rules)
        levels = [ [ seed ] ]
        used = Set[seed.id]
        loop do
          last = levels.last.last
          following = upcoming(pool, used, last, cadence, rules) { |charge| continues?(charge, levels.last, rules) }
          if following
            levels.last << following
          else
            step = rules.steps && step_from(pool, used, levels.last, cadence, rules)
            break unless step

            levels << [ step ]
          end
          used << levels.last.last.id
        end
        levels.pop if levels.size > 1 && levels.last.size < 2
        levels
      end

      # The charge closest to where the cadence expects the next one (or,
      # allowing missed periods, a later one) that satisfies the block.
      def upcoming(pool, used, last, cadence, rules, skips: rules.skips)
        (1..(1 + skips)).each do |k|
          expected = last.on + cadence.offset(k)
          tolerance = rules.tolerance_for(cadence) * k
          candidates = pool.select do |charge|
            !used.include?(charge.id) && charge.on > last.on && (charge.on - expected).abs <= tolerance && yield(charge)
          end
          best = candidates.min_by { |charge| [ (charge.on - expected).abs, (charge.amount_paise - last.amount_paise).abs ] }
          return best if best
        end
        nil
      end

      def step_from(pool, used, level, cadence, rules)
        last = level.last
        low = @settings.fetch("min_step_ratio")
        high = @settings.fetch("max_step_ratio")
        upcoming(pool, used, last, cadence, rules) do |charge|
          ratio = charge.amount_paise.fdiv(last.amount_paise)
          ratio.between?(low, high) && !continues?(charge, level, rules) && !running?(pool, used, charge, last, cadence, rules) &&
            upcoming(pool, used | [ charge.id ], charge, cadence, rules) { |other| same_price?(other, charge, rules.drift) }
        end
      end

      # Was the new price already being charged a period before, while the
      # old price was still running? Then it is another subscription running
      # alongside, not a price step. (A one-off purchase at the new price
      # off the cadence doesn't count.)
      def running?(pool, used, charge, last, cadence, rules)
        expected = charge.on - cadence.offset
        pool.any? do |other|
          !used.include?(other.id) && other.id != charge.id && (other.on - expected).abs <= rules.tolerance_for(cadence) &&
            other.on < charge.on && other.on > last.on - cadence.offset && same_price?(other, charge, rules.drift)
        end
      end

      # A price that has repeated exactly (rupee prices) must stay exact, so
      # a ₹189 → ₹199 rise is a step; one that has been moving (a USD price
      # converted every month) may drift.
      def continues?(charge, level, rules)
        if level.size >= 2 && level.all? { |other| other.amount_paise == level.first.amount_paise }
          charge.amount_paise == level.first.amount_paise
        else
          same_price?(charge, level.last, rules.drift)
        end
      end

      def same_price?(charge, reference, drift)
        (charge.amount_paise - reference.amount_paise).abs <= reference.amount_paise * drift
      end

      def findings(series)
        flagged = series.select { |item| item.active? && item.flagged }
        subscriptions = flagged.map { |item| Finding.new("subscription", item, item.amount_paise, nil, nil, nil) }
        increases = flagged.filter_map do |item|
          previous, step = item.increases.last
          Finding.new("price_increase", item, step.amount_paise, previous, step, nil) if step
        end
        duplicates = flagged.group_by(&:merchant).values.flat_map do |group|
          original, *others = group.sort_by { |item| [ item.first_charged_on, item.charges.first.id ] }
          others.map { |item| Finding.new("duplicate", item, item.amount_paise, nil, nil, original) }
        end
        subscriptions + increases + duplicates
      end
  end
end
