import { describe, expect, it } from "vitest";
import { formatPlainDate } from "./dates";

describe("formatPlainDate", () => {
  it("shows the calendar date as printed on the statement", () => {
    expect(formatPlainDate("2026-11-15")).toBe("15 Nov 2026");
    expect(formatPlainDate("2026-01-01")).toBe("1 Jan 2026");
  });

  it("doesn't drift with the device's time zone", () => {
    // A Date at midnight UTC renders as 31 Dec in the Americas; a PlainDate can't.
    const tz = process.env.TZ;
    process.env.TZ = "America/Los_Angeles";
    try {
      expect(formatPlainDate("2026-01-01")).toBe("1 Jan 2026");
    } finally {
      process.env.TZ = tz;
    }
  });
});
