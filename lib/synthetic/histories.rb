require "json"
require "date"
require "fileutils"

module Synthetic
  # Generates labelled, entirely fabricated household transaction histories
  # for the recurring-charge detection eval (eval/detection/README.md):
  #
  #   Synthetic::Histories.new(seed: 7).histories(40)
  #   # => [#<History id="h7-001" as_of=2026-08-31 txns=[[1, "netflix", "streaming", 2025-03-05, -64900, "netflix-1", "charge"], ...]>]
  #
  # Each transaction is [id, merchant, category, date, signed paise, series
  # key or nil, role]. Roles: "charge" (part of a series), "noise" (an
  # ordinary purchase), "refund" (money back for a purchase), "mandate" (₹1
  # or ₹2 AutoPay set-up and card verification), "reversal" (a failed
  # renewal debited and credited back), "trial" (a charge refunded in full).
  #
  # `series` holds the ground truth per key: kind "subscription" (worth
  # flagging) or "commitment" (SIPs, EMIs, rent, insurance, utilities, card
  # bills), cadence, status, whether it is detectable at all, the price
  # increase if any, and which series a second subscription duplicates.
  #
  # The messiness is deliberate: charges land a few days late and slip past
  # weekends, renewals fail and are skipped, 28-day prepaid plans drift
  # against the calendar, USD prices move with the exchange rate,
  # commitments step up, utility bills follow usage, people order the same
  # meal and take the same ride over and over, and second subscriptions run
  # alongside the first at the same merchant.
  class Histories
    History = Data.define(:id, :as_of, :txns, :series) do
      def to_json(*)
        { id: id, as_of: as_of.iso8601,
          txns: txns.map { |id, merchant, category, on, amount, key, role| [ id, merchant, category, on.iso8601, amount, key, role ] },
          series: series }.to_json(*)
      end
    end

    # Plans per cadence; :days for prepaid plans that renew every N days.
    SUBSCRIPTIONS = {
      "netflix" => { "monthly" => [ 149_00, 199_00, 499_00, 649_00 ] },
      "amazon_prime" => { "monthly" => [ 299_00 ], "quarterly" => [ 599_00 ], "annual" => [ 1_499_00 ] },
      "jiohotstar" => { "monthly" => [ 149_00, 299_00 ], "quarterly" => [ 499_00 ], "annual" => [ 1_499_00 ] },
      "sonyliv" => { "monthly" => [ 399_00 ], "half_yearly" => [ 699_00 ], "annual" => [ 1_499_00 ] },
      "spotify" => { "monthly" => [ 59_00, 119_00, 149_00, 179_00 ] },
      "youtube_premium" => { "monthly" => [ 129_00, 149_00, 189_00 ] },
      "google_one" => { "monthly" => [ 35_00, 130_00, 210_00 ], "annual" => [ 650_00, 1_300_00 ] },
      "google_play" => { "monthly" => [ 99_00, 199_00 ] },
      "apple" => { "monthly" => [ 99_00, 179_00, 195_00 ] },
      "microsoft" => { "monthly" => [ 489_00, 619_00 ], "annual" => [ 4_899_00 ] },
      "adobe" => { "monthly" => [ 1_675_00, 4_230_00 ] },
      "openai" => { "monthly" => [ 1_999_00 ] },
      "times_prime" => { "annual" => [ 1_199_00 ] },
      "jio" => { "monthly" => [ 249_00, 299_00, 349_00 ], "quarterly" => [ 719_00, 799_00 ], days: { "monthly" => 28, "quarterly" => 84 } },
      "airtel" => { "monthly" => [ 399_00, 449_00, 599_00 ] },
      "vi" => { "monthly" => [ 299_00, 349_00 ], days: { "monthly" => 28 } },
      "act_fibernet" => { "monthly" => [ 699_00, 999_00, 1_199_00 ], "quarterly" => [ 2_097_00 ] },
      "tata_play" => { "monthly" => [ 299_00, 399_00, 499_00 ] },
      "cultfit" => { "monthly" => [ 999_00, 1_499_00 ], "quarterly" => [ 3_499_00 ] },
      "byjus" => { "monthly" => [ 1_999_00, 2_999_00 ] },
      "swiggy" => { "quarterly" => [ 299_00, 499_00 ] } # Swiggy One, among food orders
    }.freeze

    # Billed in dollars: rupees move with the exchange rate every month.
    USD = { "openai" => 20.0, "adobe" => 22.99, "microsoft" => 9.99, "google_one" => 1.99 }.freeze

    MONTHS = { "monthly" => 1, "quarterly" => 3, "half_yearly" => 6, "annual" => 12 }.freeze

    NOISE = {
      %w[ swiggy zomato ] => { per_month: 0..10, amounts: 89_00..1_800_00, usual: 0.25 },
      %w[ blinkit zepto bigbasket dmart ] => { per_month: 0..6, amounts: 99_00..4_000_00, usual: 0.1 },
      %w[ amazon flipkart myntra ] => { per_month: 0..3, amounts: 199_00..9_999_00, usual: 0.0, refunds: 0.1 },
      %w[ uber ola rapido ] => { per_month: 0..9, amounts: 60_00..700_00, usual: 0.5, whole_rupees: true },
      %w[ indian_oil ] => { per_month: 0..5, amounts: [ 300_00, 500_00, 1_000_00, 2_000_00 ] },
      %w[ irctc makemytrip ] => { per_month: 0..1, amounts: 120_00..9_000_00 },
      %w[ apollo_pharmacy ] => { per_month: 0..2, amounts: 80_00..2_500_00, usual: 0.3 },
      %w[ google_play apple ] => { per_month: 0..2, amounts: [ 10_00, 49_00, 99_00, 199_00, 299_00 ] },
      %w[ paytm ] => { per_month: 0..2, amounts: [ 100_00, 200_00, 500_00 ] },
      %w[ zerodha ] => { per_month: 0..1, amounts: [ 5_000_00, 10_000_00, 25_000_00 ] }
    }.freeze

    def self.write_jsonl(path, histories)
      FileUtils.mkdir_p(File.dirname(path.to_s))
      File.write(path, histories.map(&:to_json).join("\n") + "\n")
    end

    def initialize(seed:, categories: Merchants::Catalogue.entries.to_h { |entry| [ entry.slug, entry.category ] })
      @seed = seed
      @rng = Random.new(seed)
      @categories = categories
    end

    def histories(count) = (1..count).map { |n| history(format("h%d-%03d", @seed, n)) }

    private
      attr_reader :rng

      def history(id)
        @as_of = Date.new(2026, rng.rand(5..10), -1)
        @start = (@as_of << rng.rand(13..24)) + 1
        @rows = []
        @truth = {}
        @counts = Hash.new(0)
        @rates = {}

        subscriptions
        commitments
        noise
        decoys
        finish(id)
      end

      # Rows: { merchant:, on:, amount:, key:, role:, step: }
      def row(merchant, on, amount, key: nil, role: "noise", step: false)
        @rows << { merchant: merchant, on: on, amount: amount, key: key, role: role, step: step, seq: @rows.size }
      end

      def subscriptions
        merchants = SUBSCRIPTIONS.keys.sample(rng.rand(2..6), random: rng)
        merchants.each { |slug| subscription(slug) }
        monthly = @truth.select { |_, info| info[:cadence] == "monthly" && info[:status] == "active" && !info[:days] }
        return unless monthly.any? && chance(0.2)

        key, info = monthly.to_a.sample(random: rng)
        subscription(info[:merchant], cadence: "monthly", duplicate_of: key)
      end

      def subscription(slug, cadence: nil, duplicate_of: nil)
        plans = SUBSCRIPTIONS.fetch(slug)
        cadences = plans.except(:days).keys
        cadence ||= weighted(cadences.to_h { |name| [ name, name == "monthly" ? 6 : 1 ] })
        days = plans.dig(:days, cadence)
        usd = USD[slug] if cadence == "monthly" && (slug == "openai" || chance(0.3))
        amount = pick(plans.fetch(cadence))
        key = next_key(slug)
        info = { merchant: slug, cadence: cadence, kind: "subscription", status: "active", duplicate_of: duplicate_of, days: days }
        @truth[key] = info

        period = days || (MONTHS.fetch(cadence) * 30.44)
        first = if duplicate_of
          original = @truth.fetch(duplicate_of)[:first]
          day = ((original.day + rng.rand(8..20) - 1) % 28) + 1
          on = @start + rng.rand(0..[ (@as_of - @start).to_i - 100, 0 ].max)
          Date.new(on.year, on.month, day)
        elsif chance(0.6)
          @start - rng.rand(0..400)
        else
          @start + rng.rand(0..(@as_of - @start).to_i)
        end
        info[:first] = first

        stop = @as_of
        if cadence != "annual" && cadence != "half_yearly" && !duplicate_of && chance(0.2)
          stop = @as_of - rng.rand((2 * period + 10).round..(2 * period + 240).round)
          info[:status] = "ended"
        end
        dates = schedule(first, stop, cadence, days)
        return if dates.empty?

        step = dates.size >= 4 && chance(0.25) ? rng.rand(2..(dates.size - 2)) : nil
        missed = dates.size >= 5 && chance(0.1) ? rng.rand(1..(dates.size - 2)) : nil
        missed = nil if missed == step
        new_amount = step && stepped(amount, plans.fetch(cadence))
        mandate(slug, dates.first) if !usd && chance(0.4)

        dates.each_with_index do |due, index|
          next if index == missed

          level = step && index >= step ? new_amount : amount
          paise = usd ? (usd * (level.fdiv(amount)) * rate(due) * 1.035 * 100).round : level
          row(slug, late(due), -paise, key: key, role: "charge", step: index == step)
        end
      end

      # Mostly up to the next plan or a typical price rise; sometimes down.
      def stepped(amount, plans)
        return plans.select { |plan| plan < amount }.max || (amount * 0.8).round(-2) - 1_00 if chance(0.15)

        plans.select { |plan| plan > amount }.min || (amount * rng.rand(1.15..1.35)).round(-4) - 1_00
      end

      def schedule(first, stop, cadence, days)
        dates = []
        k = 0
        loop do
          due = days ? first + days * k : first >> (MONTHS.fetch(cadence) * k)
          break if due > stop

          dates << due if due >= @start - 3
          k += 1
        end
        dates
      end

      # Charges land a little late, and debits due on a weekend slip to Monday.
      def late(due)
        on = chance(0.75) ? due : due + rng.rand(1..3)
        on += 1 while on.saturday? || on.sunday? if chance(0.5)
        on
      end

      def mandate(slug, first)
        on = first - rng.rand(0..2)
        row(slug, on, -1_00, role: "mandate")
        row(slug, on + rng.rand(1..3), 1_00, role: "mandate") if chance(0.5)
      end

      # Monthly USD/INR random walk around 84-87.
      def rate(on)
        month = [ on.year, on.month ]
        @rates[month] ||= begin
          previous = @rates.values.last || rng.rand(84.0..87.0)
          (previous * (1 + rng.rand(-0.012..0.012))).round(4)
        end
      end

      def commitments
        rng.rand(0..3).times do
          commitment(pick(%w[ hdfc_mf sbi_mf groww iccl ]), "monthly", pick([ 500_00, 1_000_00, 2_000_00, 2_500_00, 5_000_00, 10_000_00 ]),
            step_up: chance(0.3) ? 1.1 : nil)
        end
        commitment("bajaj_finance", "monthly", pick([ 1_850_00, 2_207_00, 3_333_00, 4_999_00 ])) if chance(0.4)
        commitment("nobroker", "monthly", pick([ 18_000_00, 22_000_00, 25_000_00 ]), step_up: 1.05) if chance(0.4)
        rng.rand(0..2).times do
          slug = pick(%w[ lic hdfc_life icici_prulife star_health ])
          cadence = slug == "star_health" ? "annual" : pick(%w[ monthly quarterly half_yearly annual ])
          commitment(slug, cadence, pick([ 1_800_00, 2_356_00, 2_500_00, 4_712_00, 6_000_00, 12_500_00 ]))
        end
        utility(pick(%w[ msedcl tata_power adani_electricity cesc ]), 1, 600_00..3_000_00)
        utility("mahanagar_gas", 2, 300_00..900_00) if chance(0.5)
        utility("cred", 1, 2_000_00..40_000_00, seasonal: false) if chance(0.5)
      end

      def commitment(slug, cadence, amount, step_up: nil)
        key = next_key(slug)
        @truth[key] = { merchant: slug, cadence: cadence, kind: "commitment", status: "active" }
        first = @start - rng.rand(0..(MONTHS.fetch(cadence) * 30))
        schedule(first, @as_of, cadence, nil).each do |due|
          years = step_up ? ((due - first) / 365).floor : 0
          paise = years.zero? ? amount : (amount * step_up**years).round(-4)
          on = due
          on += 1 while on.saturday? || on.sunday?
          row(slug, on, -paise, key: key, role: "charge")
        end
      end

      # Usage-priced bills: a different amount every time.
      def utility(slug, every, range, seasonal: true)
        key = next_key(slug)
        @truth[key] = { merchant: slug, cadence: every == 1 ? "monthly" : "bimonthly", kind: "commitment", status: "active" }
        base = rng.rand(range)
        first = @start - rng.rand(0..(every * 30))
        k = 0
        while (due = first >> (every * k)) <= @as_of
          season = seasonal ? 1 + 0.35 * Math.sin(due.month * Math::PI / 6) : 1
          row(slug, late(due) + rng.rand(0..6), -(base * season * rng.rand(0.7..1.3)).round, key: key, role: "charge")
          k += 1
        end
      end

      def noise
        month = Date.new(@start.year, @start.month, 1)
        usual = {}
        while month <= @as_of
          NOISE.each do |merchants, spec|
            rng.rand(spec.fetch(:per_month)).times do
              slug = pick(merchants)
              on = month + rng.rand(0..27)
              usual[slug] ||= amount(spec)
              paise = chance(spec.fetch(:usual, 0)) ? usual[slug] : amount(spec)
              row(slug, on, -paise)
              row(slug, on + rng.rand(3..20), paise, role: "refund") if chance(spec.fetch(:refunds, 0))
            end
          end
          month = month.next_month
        end
      end

      def amount(spec)
        amounts = spec.fetch(:amounts)
        paise = amounts.is_a?(Range) ? rng.rand(amounts) : pick(amounts)
        spec[:whole_rupees] ? paise.round(-2) : paise
      end

      # Things that repeat or look like charges but are not subscriptions.
      def decoys
        if chance(0.25) # renewals that keep failing: debited and reversed
          slug = pick(SUBSCRIPTIONS.keys)
          paise = pick(SUBSCRIPTIONS.fetch(slug).except(:days).values.flatten)
          first = @start + rng.rand(0..[ (@as_of - @start).to_i - 150, 0 ].max)
          rng.rand(3..5).times do |k|
            on = late(first >> k)
            row(slug, on, -paise, role: "reversal")
            row(slug, on + rng.rand(0..2), paise, role: "reversal")
          end
        end
        if chance(0.2) # repeated card verifications and mandate set-ups
          slug = pick(SUBSCRIPTIONS.keys)
          first = @start + rng.rand(0..[ (@as_of - @start).to_i - 200, 0 ].max)
          rng.rand(4..6).times { |k| row(slug, late(first >> k), -pick([ 1_00, 2_00 ]), role: "mandate") }
        end
        rng.rand(0..2).times do # free trials that charged, then refunded in full
          slug = pick(SUBSCRIPTIONS.keys)
          on = @start + rng.rand(0..(@as_of - @start).to_i)
          paise = pick(SUBSCRIPTIONS.fetch(slug).except(:days).values.flatten)
          row(slug, on, -paise, role: "trial")
          row(slug, on + rng.rand(1..10), paise, role: "trial")
        end
      end

      def finish(id)
        rows = @rows.select { |r| r[:on].between?(@start, @as_of) }.sort_by { |r| [ r[:on], r[:seq] ] }
        rows.each.with_index(1) { |r, index| r[:id] = index }
        by_key = rows.select { |r| r[:key] }.group_by { |r| r[:key] }
        series = @truth.filter_map do |key, info|
          charges = by_key.fetch(key, [])
          next if charges.empty?

          [ key, truth(info, charges) ]
        end.to_h
        # Which of two subscriptions at one merchant is the second one is
        # decided by what the statement shows: the one that appears later.
        series.each do |key, info|
          original = series[info[:duplicate_of]]
          next unless original && by_key.fetch(key).first[:on] < by_key.fetch(info[:duplicate_of]).first[:on]

          original[:duplicate_of] = key
          info[:duplicate_of] = nil
        end
        series.each_value { |info| info[:duplicate_of] = nil unless series.key?(info[:duplicate_of]) }
        txns = rows.map do |r|
          [ r[:id], r[:merchant], @categories.fetch(r[:merchant]), r[:on], r[:amount], series.key?(r[:key]) ? r[:key] : nil, r[:role] ]
        end
        History.new(id, @as_of, txns, series)
      end

      def truth(info, charges)
        step = charges.index { |r| r[:step] }
        increase = nil
        if step&.positive? && charges.size - step >= 2 && -charges[step][:amount] > -charges[step - 1][:amount]
          increase = { previous_amount_paise: -charges[step - 1][:amount], txn: charges[step][:id] }
        end
        minimum = info[:cadence] == "annual" ? 2 : 3
        { merchant: info[:merchant], category: @categories.fetch(info[:merchant]), cadence: info[:cadence], kind: info[:kind],
          status: info[:status], charges: charges.size, detectable: info[:kind] == "subscription" && charges.size >= minimum,
          increase: increase, duplicate_of: info[:duplicate_of] }
      end

      def next_key(slug) = "#{slug}-#{@counts[slug] += 1}"
      def chance(probability) = rng.rand < probability
      def pick(list) = list.to_a.sample(random: rng)

      def weighted(weights)
        target = rng.rand * weights.values.sum
        weights.each { |key, weight| return key if (target -= weight) < 0 }
        weights.keys.last
      end
  end
end
