module Synthetic
  # Renders synthetic SBI statements in the same `pdftotext -layout` shape as
  # spec/fixtures/synthetic/sbi/sample_statement.layout.txt (column offsets,
  # wrapped narrations, "-" placeholders, page headers and footers), so the
  # parser, reconciler and importer can be tested on unlimited data with
  # known ground truth. Everything here is fabricated.
  module SbiStatement
    Txn = Data.define(:posted_on, :narration, :amount_paise)

    DETAILS_COL = 23
    DETAILS_WIDTH = 37
    REF_END = 75
    DEBIT_END = 89
    CREDIT_END = 99
    BALANCE_END = 109
    ROWS_PER_PAGE = 5

    MERCHANTS = [
      %w[ NETFLIX YESB netflix@ybl Mandate ], %w[ CLOUD\ STORAGE YESB cloudpay@yesbank Mandate ],
      %w[ METRO\ MART HDFC metromart@hdfcbank Groceries ], %w[ CITY\ POWER\ CORP SBIN citypower@sbi Electricity\ Bill ],
      %w[ MUSIC\ APP ICIC musicapp@icici Subscription ], %w[ FRESH\ HARVEST PUNB freshharvest@pnb Weekly\ Order ]
    ].freeze
    PEOPLE = [ "ANANYA ROY", "ROHAN DAS", "MEERA IYER", "KABIR SEN" ].freeze

    module_function

    # A random but reproducible account history between two dates.
    def history(rng, from:, to:, per_day: 0..2)
      (from..to).flat_map do |day|
        Array.new(rng.rand(per_day)) { random_txn(rng, day) }.tap do |txns|
          txns << txns.last.with(narration: txns.last.narration) if txns.any? && rng.rand < 0.08 # identical twin charge
        end
      end
    end

    def random_txn(rng, day)
      ref = rng.rand(10**11..(10**12 - 1))
      if rng.rand < 0.2
        person = PEOPLE.sample(random: rng)
        Txn.new(day, "DEP TFR UPI/CR/#{ref}/#{person}/UTIB/#{person.split.first.downcase}@okaxis/Transfer " \
          "00977#{rng.rand(10**8)} AT 09482 BIDHANNAGAR", rng.rand(500_00..20_000_00))
      else
        name, bank, vpa, note = MERCHANTS.sample(random: rng)
        Txn.new(day, "WDL TFR UPI/DR/#{ref}/#{name}/#{bank}/#{vpa}/#{note} 00976#{rng.rand(10**8)} AT 09482 BIDHANNAGAR",
          -[ 99_00, 149_00, 199_00, 649_00, rng.rand(50_00..5_000_00) ].sample(random: rng))
      end
    end

    # Statement text for the transactions dated within [from, to] of a history
    # that started at `opening_paise`.
    def statement_for(history, from:, to:, opening_paise:, account_number: "39481029475", statement_date: to)
      before = history.select { |t| t.posted_on < from }
      rows = history.select { |t| t.posted_on.between?(from, to) }
      render(rows: rows, opening_paise: opening_paise + before.sum(&:amount_paise),
        from: from, to: to, account_number: account_number, statement_date: statement_date)
    end

    def render(rows:, opening_paise:, from:, to:, account_number: "39481029475", statement_date: to)
      balance = opening_paise
      body = rows.map do |txn|
        balance += txn.amount_paise
        row_lines(txn, balance)
      end
      pages = body.each_slice(ROWS_PER_PAGE).to_a.presence || [ [] ]

      out = header(account_number: account_number, from: from, to: to, statement_date: statement_date, closing: balance)
      pages.each_with_index do |page_rows, index|
        page_header = table_header
        page_header[0] = "\f#{page_header[0]}" if index.positive? # pdftotext's page break marker
        out.concat(page_header)
        page_rows.each { |lines| out.concat(lines) }
        out << "" << "Statement of Account (Synthetic Data)#{" " * 60}Page #{index + 1} of #{pages.size}"
      end
      out.join("\n").concat("\n")
    end

    def header(account_number:, from:, to:, statement_date:, closing:)
      side = closing.negative? ? "DR" : "CR"
      [
        "    STATE BANK                                              Welcome:",
        "    Account Summary          As on #{statement_date.strftime("%d-%m-%Y")}",
        "                                    STATEMENT OF ACCOUNT",
        "  Date of Statement      : #{statement_date.strftime("%d-%m-%Y")}       Branch Code          : 09482",
        "  Clear Balance          : #{Paise.format(closing.abs, symbol: "")} #{side}",
        "                                                             Account Number       : #{account_number}",
        "                                                             IFSC Code            : SBIN0009482",
        "                                     Statement From : #{from.strftime("%d-%m-%Y")} to #{to.strftime("%d-%m-%Y")}",
        ""
      ]
    end

    def table_header
      [
        " Value#{" " * 64}Ref No/",
        " Date          Post Date Details#{" " * 38}Cheque       Debit     Credit    Balance",
        "#{" " * 72}No"
      ]
    end

    def row_lines(txn, balance)
      date = txn.posted_on.strftime("%d/%m/%Y")
      wrapped = wrap(txn.narration)
      debit = txn.amount_paise.negative? ? Paise.format(-txn.amount_paise, symbol: "") : "-"
      credit = txn.amount_paise.positive? ? Paise.format(txn.amount_paise, symbol: "") : "-"

      first = " #{date} #{date} #{wrapped.first}"
      first = place(first, "-", REF_END)
      first = place(first, debit, DEBIT_END)
      first = place(first, credit, CREDIT_END)
      first = place(first, Paise.format(balance.abs, symbol: "") + (balance.negative? ? " DR" : ""), BALANCE_END)
      [ first, *wrapped.drop(1).map { |line| "#{" " * DETAILS_COL}#{line}" } ]
    end

    # Right-align `text` so it ends at column `right_edge`, at least one space
    # after what is already on the line.
    def place(line, text, right_edge)
      start = [ right_edge - text.length, line.length + 1 ].max
      line.ljust(start) + text
    end

    # Chromium-style wrapping: break at spaces, split over-long words.
    def wrap(text)
      lines = [ +"" ]
      text.split(" ").each do |word|
        word.scan(/.{1,#{DETAILS_WIDTH}}/).each do |piece|
          if lines.last.empty? then lines.last << piece
          elsif lines.last.length + 1 + piece.length <= DETAILS_WIDTH then lines.last << " " << piece
          else lines << piece.dup
          end
        end
      end
      lines
    end
  end
end
