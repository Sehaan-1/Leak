import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import { getMe } from "./api/client";
import { Dashboard } from "./components/Dashboard";
import { LiveAnnouncer } from "./components/LiveAnnouncer";
import { SignIn } from "./components/SignIn";

export function App() {
  const queryClient = useQueryClient();
  const me = useQuery({ queryKey: ["me"], queryFn: getMe });
  const view = me.data ? "dashboard" : me.data === null ? "sign-in" : "loading";

  // Move focus to the new page heading when the view changes (sign in, sign
  // out), but not on first load, where the browser's own focus is right.
  const [focusHeading, setFocusHeading] = useState(false);
  const lastView = useRef<string | null>(null);
  useEffect(() => {
    if (view === "loading") return;
    if (lastView.current !== null && lastView.current !== view) setFocusHeading(true);
    // After sign-out, forget the household's data. This runs once the
    // dashboard has unmounted, so no observer re-creates the queries.
    if (view === "sign-in") queryClient.removeQueries({ predicate: (query) => query.queryKey[0] !== "me" });
    lastView.current = view;
  }, [view, queryClient]);

  if (me.isError) {
    return (
      <main className="page">
        <h1>Leak can't reach the server</h1>
        <p>{me.error.message}</p>
        <button type="button" onClick={() => me.refetch()}>
          Try again
        </button>
      </main>
    );
  }

  return (
    <>
      {me.data ? (
        <Dashboard me={me.data} focusHeading={focusHeading} />
      ) : me.data === null ? (
        <SignIn focusHeading={focusHeading} />
      ) : (
        <p className="page" role="status">
          Loading…
        </p>
      )}
      <LiveAnnouncer />
    </>
  );
}
