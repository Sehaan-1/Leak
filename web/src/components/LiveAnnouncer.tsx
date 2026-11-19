import { ANNOUNCER_ID } from "../lib/fieldErrors";

/** The page's single polite live region for field errors (see lib/fieldErrors.ts). */
export function LiveAnnouncer() {
  return <div id={ANNOUNCER_ID} aria-live="polite" className="visually-hidden" />;
}
