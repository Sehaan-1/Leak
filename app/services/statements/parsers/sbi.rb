module Statements
  module Parsers
    # State Bank of India account statement (net banking / YONO PDF), read from
    # `pdftotext -layout` output.
    #
    # Columns are located from each page's table header, because their
    # character offsets move between pages. A transaction starts on a line
    # with two dates (value date, post date); its narration wraps onto
    # continuation lines indented to the Details column. Amounts are assigned
    # to Debit / Credit / Balance by whichever header edge they sit closest to
    # (they are right-aligned), so "-" placeholders and blank cells both work.
    # Footers and disclaimers start left of the Details column and end a row.
    class Sbi
      DATE = %r{\d{2}/\d{2}/\d{4}}
      ROW_START = %r{\A\s*#{DATE}\s+#{DATE}\s+\S}
      AMOUNT = /\A[\d,]+\.\d{2}\z/
      AMOUNT_WITH_SIDE = /\A(?<amount>[\d,]+\.\d{2})(?<side>CR|DR)?\z/i
      SIDE = /\A(CR|DR)\z/i

      Token = Data.define(:text, :from, :to)
      Columns = Data.define(:details_from, :ref_from, :ref_to, :debit_to, :credit_to, :balance_to)

      def self.matches?(text)
        text.match?(/IFSC\s+Code\s*:\s*SBIN/i) && text.match?(/Post\s+Date|Txn\s+Date/i)
      end

      def self.parse(text)
        new(text).parse
      end

      def initialize(text)
        # pdftotext marks page breaks with \f at the start of the next page's
        # first line; it occupies no column, so drop it.
        @lines = text.delete("\f").split("\n").map(&:rstrip)
      end

      def parse
        rows = parse_rows
        raise ParseError, "No transactions found in this statement." if rows.empty?

        period_from, period_to = header_period || [ rows.first.posted_on, rows.last.posted_on ]
        ParsedStatement.new(
          bank: "sbi",
          account_number: header_value(/Account\s+Number\s*:\s*(\d{6,20})\b/) ||
            raise(ParseError, "Couldn't find the account number on the statement."),
          ifsc: header_value(/IFSC\s+Code\s*:\s*(SBIN\w{7})\b/i).to_s.upcase,
          period_from: period_from,
          period_to: period_to,
          statement_date: header_date(/Date\s+of\s+Statement\s*:\s*(\d{2}-\d{2}-\d{4})/),
          closing_balance_paise: header_balance(/Clear\s+Balance\s*:\s*([\d,]+\.\d{2})\s*(CR|DR)?/i),
          rows: rows
        )
      end

      private
        def parse_rows
          rows = []
          columns = nil
          current = nil

          @lines.each_with_index do |line, index|
            line_no = index + 1

            if header_line?(line)
              rows << finish(current) if current
              current = nil
              columns = columns_from(line, index.positive? ? @lines[index - 1] : "")
              next
            end
            next if columns.nil? || line.strip.empty?

            tokens = tokenize(line)
            if line.match?(ROW_START)
              rows << finish(current) if current
              current = { line_no: line_no, value_on: parse_date(tokens[0].text, line_no),
                          posted_on: parse_date(tokens[1].text, line_no),
                          details: [], ref: [], details_from: tokens[2].from }
              classify(tokens.drop(2), columns, current, line_no)
            elsif line.match?(/\A\s*#{DATE}/)
              raise ParseError.new("Line #{line_no} looks like a transaction but couldn't be read.", line_no: line_no)
            elsif current && continuation?(tokens, current, columns)
              classify(tokens, columns, current, line_no)
            else
              rows << finish(current) if current # footer, disclaimer, page number
              current = nil
            end
          end
          rows << finish(current) if current
          rows
        end

        def header_line?(line)
          line.match?(/(Post|Txn)\s+Date/i) && line.match?(/Details|Description/i) &&
            line.match?(/Debit/i) && line.match?(/Credit/i) && line.match?(/Balance/i)
        end

        def columns_from(line, previous_line)
          ref_candidates = [ line =~ /Ref|Cheque|Chq/i, previous_line =~ /Ref|Cheque|Chq/i ].compact
          debit_from = line =~ /Debit/i
          ref_label_end = tokenize(line).select { |t| ref_candidates.any? && t.from >= ref_candidates.min && t.to <= debit_from }.map(&:to).max
          Columns.new(
            details_from: line =~ /Details|Description/i,
            ref_from: ref_candidates.min || debit_from,
            ref_to: ref_label_end || debit_from,
            debit_to: debit_from + "Debit".length,
            credit_to: (line =~ /Credit/i) + "Credit".length,
            balance_to: (line =~ /Balance/i) + "Balance".length
          )
        end

        def tokenize(line)
          line.to_enum(:scan, /\S+/).map do
            match = Regexp.last_match
            Token.new(text: match[0], from: match.begin(0), to: match.end(0))
          end
        end

        def continuation?(tokens, current, columns)
          first = tokens.first
          first.from >= current[:details_from] - 3 && first.from < columns.ref_from - 1 ||
            first.from >= columns.ref_from - 2 # amounts or reference spilling onto the next line
        end

        # Peel amounts off the right edge, then the reference column, and keep
        # the rest as narration.
        def classify(tokens, columns, row, line_no)
          tokens = tokens.dup
          while (token = tokens.last) && token.from >= columns.ref_from - 2
            slot = nearest_slot(token, columns)
            if slot == :balance && token.text.match?(SIDE)
              row[:balance_side] = token.text.upcase
            elsif slot != :ref && amountish?(token, slot)
              if row.key?(slot)
                raise ParseError.new("Line #{line_no}: two values in the #{slot} column.", line_no: line_no)
              end
              row[slot] = token.text
            else
              break
            end
            tokens.pop
          end

          ref_tokens = []
          ref_tokens.unshift(tokens.pop) while tokens.last && tokens.last.from >= columns.ref_from - 2
          row[:ref] << ref_tokens.map(&:text).join(" ") if ref_tokens.any?
          row[:details] << tokens.map(&:text).join(" ") if tokens.any?
        end

        def nearest_slot(token, columns)
          { ref: columns.ref_to, debit: columns.debit_to, credit: columns.credit_to, balance: columns.balance_to }
            .min_by { |_, edge| (token.to - edge).abs }.first
        end

        def amountish?(token, slot)
          return token.text.match?(AMOUNT_WITH_SIDE) if slot == :balance

          token.text == "-" || token.text.match?(AMOUNT)
        end

        def finish(row)
          line_no = row[:line_no]
          raise ParseError.new("Line #{line_no}: transaction has no balance.", line_no: line_no) unless row[:balance]

          balance = row[:balance].match(AMOUNT_WITH_SIDE)
          side = balance[:side] || row[:balance_side]
          balance_paise = Paise.parse(balance[:amount])
          debit = amount_or_zero(row[:debit])
          credit = amount_or_zero(row[:credit])
          if [ debit, credit ].count(&:positive?) != 1
            raise ParseError.new("Line #{line_no}: a transaction needs exactly one of debit or credit.", line_no: line_no)
          end

          ref = row[:ref].join(" ").squish
          Row.new(
            line_no: line_no,
            value_on: row[:value_on],
            posted_on: row[:posted_on],
            narration: row[:details].join(" ").squish,
            ref: ref == "-" ? nil : ref.presence,
            debit_paise: debit,
            credit_paise: credit,
            balance_paise: side&.upcase == "DR" ? -balance_paise : balance_paise
          )
        end

        def amount_or_zero(text)
          text.nil? || text == "-" ? 0 : Paise.parse(text)
        end

        def parse_date(text, line_no)
          Date.strptime(text, "%d/%m/%Y")
        rescue Date::Error
          raise ParseError.new("Line #{line_no}: #{text.inspect} is not a valid date.", line_no: line_no)
        end

        def header_value(pattern)
          @lines.each { |line| (m = line.match(pattern)) and return m[1] }
          nil
        end

        def header_period
          @lines.each do |line|
            m = line.match(/Statement\s+From\s*:\s*(\d{2}-\d{2}-\d{4})\s+to\s+(\d{2}-\d{2}-\d{4})/i) or next
            return [ Date.strptime(m[1], "%d-%m-%Y"), Date.strptime(m[2], "%d-%m-%Y") ]
          end
          nil
        end

        def header_date(pattern)
          value = header_value(pattern)
          value && Date.strptime(value, "%d-%m-%Y")
        end

        def header_balance(pattern)
          @lines.each do |line|
            m = line.match(pattern) or next
            paise = Paise.parse(m[1])
            return m[2]&.upcase == "DR" ? -paise : paise
          end
          nil
        end
    end
  end
end
