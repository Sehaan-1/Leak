module Merchants
  # Splits a bank narration into the parts that identify the counterparty.
  #
  #   Merchants::Narration.parse("WDL TFR UPI/DR/412345678901/NETFLIX/YESB/netflix@ybl/Mandate 00976 AT 09482 X")
  #   # => #<data Parsed channel=:upi, payee="NETFLIX", vpa="netflix@ybl", vpa_local="netflix", text="...">
  #
  # Statement text wraps at a fixed width and the importer joins the pieces
  # with spaces, so a space can appear anywhere, even inside "UPI/DR/" or a
  # UPI ID. Structured formats (UPI, NEFT, IMPS) are therefore parsed with
  # all whitespace removed; names are compared as space-free keys anyway
  # (Merchants::Text.key). The amount and its sign come from the statement
  # columns, never from here.
  module Narration
    Parsed = Data.define(:channel, :payee, :vpa, :vpa_local, :text) do
      def payee_key = Text.key(payee)
    end

    # Matched against Text.key(narration): A-Z0-9 only.
    CASH = /ATMWDL|ATMCASH|ATMWD|CASHWDL|CASHWITHDRAWAL|CASHDEPOSIT|CSHDEP|CASHDEP/
    BANK = /CREDITINTEREST|INTPD|INTEREST(CREDIT|PAID|CR)|SBINTPD|SMSCH(AR)?G|ANNUALFEE|ATMAMC|CARDAMC|DEBITCARDFEE|
      MINBAL|NONMAINT|AVGBAL|CHGS|CHARGES|\AGST|GSTON|SERVICECHARGE|CHQBOOK|CHEQUEBOOK|STOPPAYMENT|ECSRETURN|NACHRETURN|
      INSUFFICIENTBAL/x
    # Matched against the whitespace-free narration.
    UPI = %r{UPI/(?:DR|CR|REV|RFND|P2A|P2M)/\d*/(.*)}i
    NEFT = %r{(?:NEFT|RTGS)(?:\*[^*]*\*[^*]*\*([^*]+)|/(?:UTR)?[A-Z0-9]*/([^/]+))}i
    IMPS = %r{IMPS/(?:P2A|P2P|P2M)?/?\d*/([^/]+)}i
    # Matched against the narration as printed.
    NACH = /ACH\s*D\s*R|NACH|ECS\s*DR/i
    BILL = /BILL\s*PAY|BBPS/i
    CARD = /DEBIT\s*CARD|\bPOS\b|OTHPG|ECOM|\d{4,6}X{4,}\d{4}/i

    module_function

    def parse(narration)
      text = narration.to_s
      compact = Text.compact(text)
      key = Text.key(text)

      if key.match?(CASH) then Parsed.new(:cash, nil, nil, nil, text)
      elsif (m = compact.match(UPI)) then upi(m[1], text)
      elsif (m = compact.match(NEFT)) then Parsed.new(:neft, (m[1] || m[2]).sub(/\d.*/, ""), nil, nil, text)
      elsif (m = compact.match(IMPS)) then Parsed.new(:imps, m[1], nil, nil, text)
      elsif key.match?(BANK) then Parsed.new(:bank, nil, nil, nil, text)
      elsif text.match?(NACH) then Parsed.new(:nach, nil, nil, nil, text)
      elsif text.match?(BILL) then Parsed.new(:bill, nil, nil, nil, text)
      elsif text.match?(CARD) then Parsed.new(:card, nil, nil, nil, text)
      else Parsed.new(:other, nil, nil, nil, text)
      end
    end

    # "PAYEE/BANK/upi@id/note..." -- the UPI ID may be cut short by the bank,
    # with or without its "@domain".
    def upi(rest, text)
      payee, _bank, raw_vpa = rest.split("/")
      raw_vpa = raw_vpa.to_s.downcase
      vpa = Text.vpa(raw_vpa)
      local = raw_vpa.split("@").first.to_s
      local = nil unless local.match?(/\A[a-z0-9._-]{4,}\z/)
      Parsed.new(:upi, payee, vpa, local, text)
    end
  end
end
