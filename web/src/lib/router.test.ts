import { describe, expect, it } from "vitest";
import { href, parseRoute } from "./router";

describe("parseRoute", () => {
  it("reads each screen's hash and falls back to findings", () => {
    expect(parseRoute("#/series/42")).toEqual({ name: "series", id: 42 });
    expect(parseRoute("#/review")).toEqual({ name: "review" });
    expect(parseRoute("#/import")).toEqual({ name: "import" });
    expect(parseRoute("#/transactions")).toEqual({ name: "transactions" });
    expect(parseRoute("#/data")).toEqual({ name: "data" });
    expect(parseRoute("")).toEqual({ name: "findings" });
    expect(parseRoute("#/series/abc")).toEqual({ name: "findings" });
  });

  it("round-trips through href", () => {
    for (const hash of ["#/", "#/series/7", "#/review", "#/import", "#/transactions", "#/data"]) {
      expect(href(parseRoute(hash))).toBe(hash);
    }
  });
});
