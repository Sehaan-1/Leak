import { useEffect } from "react";

/**
 * Sets the tab title for a screen ("Review · Leak"). Not React's <title>
 * element: Rails' HTML shell already has one, and the browser uses the
 * first <title> in the document.
 */
export function useTitle(title: string): void {
  useEffect(() => {
    document.title = `${title} · Leak`;
  }, [title]);
}
