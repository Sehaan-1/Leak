# Money is Integer paise everywhere. Strings from statements are parsed
# exactly (no Float ever touches an amount) and formatted with Indian
# digit grouping: 12345678 => "₹1,23,456.78".
module Paise
  INDIAN_GROUPED = /\d{1,2}(?:,\d{2})*,\d{3}/   # 1,23,456
  WESTERN_GROUPED = /\d{1,3}(?:,\d{3})+/         # 123,456 / 1,234,567
  AMOUNT = /\A(?<sign>-)?(?<rupees>#{INDIAN_GROUPED}|#{WESTERN_GROUPED}|\d+)(?:\.(?<fraction>\d{1,2}))?\z/

  module_function

  # "1,23,456.78" => 12345678, "649" => 64900, "-0.5" => -50.
  # Accepts Indian ("1,23,456"), Western ("123,456") or no grouping. Both
  # groupings yield the same digits, so the value is unambiguous. Rejects
  # malformed grouping ("1,2,3"), >2 decimals, symbols, blanks.
  def parse(string)
    match = AMOUNT.match(string.to_s.strip)
    raise ArgumentError, "not a rupee amount: #{string.inspect}" unless match

    rupees = Integer(match[:rupees].delete(","), 10)
    paise = Integer((match[:fraction] || "0").ljust(2, "0"), 10)
    value = rupees * 100 + paise
    match[:sign] ? -value : value
  end

  def format(paise, symbol: "₹")
    raise ArgumentError, "paise must be an Integer, got #{paise.inspect}" unless paise.is_a?(Integer)

    sign = paise.negative? ? "-" : ""
    rupees, fraction = paise.abs.divmod(100)
    "#{sign}#{symbol}#{group_indian(rupees)}.#{fraction.to_s.rjust(2, "0")}"
  end

  def group_indian(rupees)
    digits = rupees.to_s
    return digits if digits.length <= 3

    head, tail = digits[0...-3], digits[-3..]
    "#{head.reverse.scan(/\d{1,2}/).join(",").reverse},#{tail}"
  end
end
