import type { SeriesSummary } from "../api/client";

type Cadence = SeriesSummary["cadence"];

/** "Monthly", for tables. */
export const CADENCE_LABEL: Record<Cadence, string> = {
  weekly: "Weekly",
  monthly: "Monthly",
  quarterly: "Every 3 months",
  half_yearly: "Every 6 months",
  annual: "Yearly",
};

/** "every month", for sentences. */
export const CADENCE_PHRASE: Record<Cadence, string> = {
  weekly: "every week",
  monthly: "every month",
  quarterly: "every 3 months",
  half_yearly: "every 6 months",
  annual: "every year",
};

/** "Dec 2025" */
export function formatMonth(iso: string, locale = "en-IN"): string {
  return Temporal.PlainDate.from(iso).toLocaleString(locale, { month: "short", year: "numeric" });
}
