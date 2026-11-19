// Statement dates are calendar dates ("2026-11-15"), not instants. Temporal's
// PlainDate keeps them free of time zones, so nobody sees the 14th because
// their device is west of UTC. Safari lacks Temporal; loadTemporal() adds the
// polyfill only where it's missing.
export async function loadTemporal(): Promise<void> {
  if (typeof globalThis.Temporal === "undefined") {
    const { Temporal } = await import("temporal-polyfill");
    Object.assign(globalThis, { Temporal });
  }
}

const dateFormat = { day: "numeric", month: "short", year: "numeric" } as const;

/** 15 Nov 2026 */
export function formatPlainDate(iso: string, locale = "en-IN"): string {
  return Temporal.PlainDate.from(iso).toLocaleString(locale, dateFormat);
}
