import { describe, expect, it } from "vitest";
import { formatRupees, formatSignedRupees, paiseToDecimal } from "./money";

describe("money", () => {
  it("formats paise as rupees with Indian digit grouping", () => {
    expect(formatRupees(24_850_75)).toBe("₹24,850.75");
    expect(formatRupees(1_00_000_00)).toBe("₹1,00,000.00");
    expect(formatRupees(12_34_56_789_01)).toBe("₹12,34,56,789.01");
    expect(formatRupees(5)).toBe("₹0.05");
  });

  it("shows the direction of a movement", () => {
    expect(formatSignedRupees(15_000_00)).toBe("+₹15,000.00");
    expect(formatSignedRupees(-1_825_00)).toBe("-₹1,825.00");
    expect(formatSignedRupees(0)).toBe("₹0.00");
  });

  it("never goes through floating point", () => {
    // 0.1 + 0.2 style errors would show up here.
    expect(paiseToDecimal(-5)).toBe("-0.05");
    expect(paiseToDecimal(Number.MAX_SAFE_INTEGER)).toBe("90071992547409.91");
    expect(formatRupees(Number.MAX_SAFE_INTEGER)).toBe("₹9,00,71,99,25,47,409.91");
  });

  it("rejects non-integer paise", () => {
    expect(() => paiseToDecimal(1.5)).toThrow(RangeError);
    expect(() => paiseToDecimal(2 ** 60)).toThrow(RangeError);
  });
});
