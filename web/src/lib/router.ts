import { useSyncExternalStore } from "react";

// Hash routes (#/series/12), so every screen is a real link that can be
// opened in a new tab or bookmarked, and Rails needs no catch-all route.
export type Route =
  | { name: "findings" }
  | { name: "series"; id: number }
  | { name: "review" }
  | { name: "import" }
  | { name: "transactions" };

export function parseRoute(hash: string): Route {
  const path = hash.replace(/^#/, "");
  const series = /^\/series\/(\d+)$/.exec(path);
  if (series?.[1]) return { name: "series", id: Number(series[1]) };
  switch (path) {
    case "/review":
      return { name: "review" };
    case "/import":
      return { name: "import" };
    case "/transactions":
      return { name: "transactions" };
    default:
      return { name: "findings" };
  }
}

export function href(route: Route): string {
  return route.name === "series"
    ? `#/series/${route.id}`
    : route.name === "findings"
      ? "#/"
      : `#/${route.name}`;
}

function subscribe(onChange: () => void) {
  window.addEventListener("hashchange", onChange);
  return () => window.removeEventListener("hashchange", onChange);
}

/** The current location hash; re-renders on navigation. */
export function useHash(): string {
  return useSyncExternalStore(subscribe, () => window.location.hash);
}
