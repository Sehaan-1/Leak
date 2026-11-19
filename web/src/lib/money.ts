// Money arrives as integer paise. Format it from a decimal *string* so no
// value is ever pushed through floating-point division.
const rupees = new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR" });
const signedRupees = new Intl.NumberFormat("en-IN", {
  style: "currency",
  currency: "INR",
  signDisplay: "exceptZero",
});

export function paiseToDecimal(paise: number): string {
  if (!Number.isSafeInteger(paise)) throw new RangeError(`Not a whole number of paise: ${paise}`);
  const sign = paise < 0 ? "-" : "";
  const abs = Math.abs(paise);
  return `${sign}${Math.trunc(abs / 100)}.${String(abs % 100).padStart(2, "0")}`;
}

type Decimal = `${number}`;

/** ₹24,850.75 (Indian digit grouping: ₹1,00,000.00). */
export function formatRupees(paise: number): string {
  return rupees.format(paiseToDecimal(paise) as Decimal);
}

/** +₹15,000.00 / -₹1,825.00 */
export function formatSignedRupees(paise: number): string {
  return signedRupees.format(paiseToDecimal(paise) as Decimal);
}
