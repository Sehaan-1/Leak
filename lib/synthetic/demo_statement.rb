module Synthetic
  # A year of one fabricated household's SBI statement, for the demo seed
  # (db/seeds.rb) and the end-to-end test. Everything here is made up, and
  # the same every time:
  #
  #   Synthetic::DemoStatement.text  # => pdftotext-shaped statement text
  #
  # What it shows off, by design:
  # - Netflix at ₹499, then ₹649 from July: a price increase.
  # - Spotify at ₹119: a plain subscription.
  # - JioHotstar twice: ₹299 since December and a second plan at ₹149 since
  #   May, billed under its old company name: a duplicate.
  # - YouTube Premium billed through Google Play, so the payee and the UPI ID
  #   name different merchants and the rules abstain: ten rows in the review
  #   queue that become a subscription once the household names the merchant.
  # - A local shop with a QR-code UPI ID the catalogue doesn't know: review.
  # - Usage-priced electricity bills, groceries, cash and family transfers:
  #   recurring or frequent, but nothing to flag.
  module DemoStatement
    FROM = Date.new(2025, 12, 1)
    TO = Date.new(2026, 11, 15)
    OPENING_PAISE = 85_000_00
    ACCOUNT_NUMBER = "39481020001"

    module_function

    def text
      SbiStatement.statement_for(txns, from: FROM, to: TO, opening_paise: OPENING_PAISE, account_number: ACCOUNT_NUMBER)
    end

    def txns
      rng = Random.new(20261119)
      rows = (0..11).flat_map { |k| month(rng, FROM >> k, k) }
      rows.select { |txn| txn.posted_on <= TO }.sort_by(&:posted_on)
    end

    def month(rng, first, k)
      rows = [
        upi_in(rng, first, "RAHUL SHARMA", "HDFC", "rahulsharma@okhdfcbank", "Monthly", 25_000_00),
        upi(rng, first + 2, "GOOGLE PLAY", "UTIB", "youtube.premium@okaxis", "YouTube Premium", 149_00),
        upi(rng, first + 4, "NETFLIX", "ICIC", "netflix@icici", "Mandate", k < 7 ? 499_00 : 649_00),
        upi(rng, first + 7, "JIOHOTSTAR", "UTIB", "jiohotstar@axisbank", "Mandate", 299_00),
        upi(rng, first + 11, "SPOTIFY INDIA", "UTIB", "spotify@axisbank", "Mandate", 119_00),
        upi(rng, first + 17, "MSEDCL", "SBIN", "msedcl@sbi", "Electricity Bill", rng.rand(1_200..2_600) * 100),
        upi(rng, first + 21, "NOVI DIGITAL ENTERTAINMENT", "ICIC", "hotstar@icici", "Mandate", 149_00),
        SbiStatement::Txn.new(first + 9, "ATM WDL ATM CASH #{rng.rand(1000..9999)} ANDHERI WEST MUMBAI", -5_000_00)
      ]
      rows.delete_at(1) if k < 2       # YouTube Premium started in February
      rows.delete_at(-2) if k < 5      # the second JioHotstar plan in May
      rows += Array.new(3) do |i|
        grocer, bank, vpa = [ %w[ SWIGGY ICIC swiggy@icici ], %w[ BLINKIT HDFC blinkit@hdfcbank ],
                              %w[ DMART HDFC dmart@hdfcbank ] ].sample(random: rng)
        upi(rng, first + 3 + (i * 9) + rng.rand(0..4), grocer, bank, vpa, "Order", rng.rand(180..1_400) * 100)
      end
      if k.in?([ 4, 9 ])
        rows << upi(rng, first + 14, "SAI KRUPA TRADERS", "YESB", "q482915736@ybl", "Payment", rng.rand(300..900) * 100)
      end
      rows
    end

    def upi(rng, on, payee, bank, vpa, note, paise)
      SbiStatement::Txn.new(on, "WDL TFR UPI/DR/#{ref(rng)}/#{payee}/#{bank}/#{vpa}/#{note} " \
        "00976#{rng.rand(10**7..(10**8 - 1))} AT 09482 ANDHERI", -paise)
    end

    def upi_in(rng, on, payee, bank, vpa, note, paise)
      SbiStatement::Txn.new(on, "DEP TFR UPI/CR/#{ref(rng)}/#{payee}/#{bank}/#{vpa}/#{note} " \
        "00977#{rng.rand(10**7..(10**8 - 1))} AT 09482 ANDHERI", paise)
    end

    def ref(rng) = rng.rand(10**11..(10**12 - 1))
  end
end
