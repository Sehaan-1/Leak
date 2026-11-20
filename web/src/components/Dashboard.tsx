import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import { listReviewItems, type Me, signOut } from "../api/client";
import { formatInstant } from "../lib/dates";
import { href, parseRoute, type Route, useHash } from "../lib/router";
import { DataScreen } from "./DataScreen";
import { FindingsScreen } from "./FindingsScreen";
import { ImportScreen } from "./ImportScreen";
import { ReviewScreen } from "./ReviewScreen";
import { SeriesScreen } from "./SeriesScreen";
import { TransactionsScreen } from "./TransactionsScreen";

const NAV: { route: Route; label: string }[] = [
  { route: { name: "findings" }, label: "Findings" },
  { route: { name: "review" }, label: "Review" },
  { route: { name: "import" }, label: "Import" },
  { route: { name: "transactions" }, label: "Transactions" },
  { route: { name: "data" }, label: "Your data" },
];

/** The signed-in app: top bar, primary navigation and the screen for the current hash. */
export function Dashboard({ me, focusHeading }: { me: Me; focusHeading: boolean }) {
  const queryClient = useQueryClient();
  const signOutMutation = useMutation({
    mutationFn: signOut,
    // App swaps to sign-in and then drops this household's cached data.
    onSuccess: () => queryClient.setQueryData(["me"], null),
  });
  const review = useQuery({ queryKey: ["review_items"], queryFn: listReviewItems });

  const hash = useHash();
  const route = parseRoute(hash);
  // After in-app navigation, move focus to the new screen's heading so
  // screen readers announce it; not on first load.
  const [navigated, setNavigated] = useState(false);
  const firstHash = useRef(hash);
  useEffect(() => {
    if (hash !== firstHash.current) setNavigated(true);
  }, [hash]);
  const focus = focusHeading || navigated;

  const current = (item: Route) =>
    item.name === route.name || (item.name === "findings" && route.name === "series");
  const reviewCount = review.data?.total_count ?? 0;
  const showCount = (item: (typeof NAV)[number]) => item.route.name === "review" && reviewCount > 0;

  return (
    <>
      <header className="topbar">
        <p className="brand">
          <a href={href({ name: "findings" })}>Leak</a>
        </p>
        <p className="who">
          {me.household.name} · <strong>{me.user.email_address}</strong>
        </p>
        <button
          type="button"
          className="secondary"
          onClick={() => signOutMutation.mutate()}
          disabled={signOutMutation.isPending}
        >
          Sign out
        </button>
        <nav aria-label="Primary" className="primary-nav">
          <ul>
            {NAV.map((item) => (
              <li key={item.route.name}>
                <a
                  href={href(item.route)}
                  aria-current={current(item.route) ? "page" : undefined}
                  // Spelled out for screen readers: visually-hidden text inside the
                  // link would come out as "Review , 12" (it's absolutely positioned).
                  aria-label={showCount(item) ? `${item.label}, ${reviewCount} to do` : undefined}
                >
                  {item.label}
                  {showCount(item) && (
                    <span className="count" aria-hidden="true">
                      {reviewCount}
                    </span>
                  )}
                </a>
              </li>
            ))}
          </ul>
        </nav>
        {me.household.demo_expires_at && (
          <p className="demo-note">
            You're trying Leak with made-up data. It's all deleted on{" "}
            {formatInstant(me.household.demo_expires_at)}.
          </p>
        )}
      </header>
      <main className="page" key={hash}>
        {route.name === "findings" ? (
          <FindingsScreen focus={focus} reviewCount={reviewCount} />
        ) : route.name === "series" ? (
          <SeriesScreen id={route.id} focus={focus} />
        ) : route.name === "review" ? (
          <ReviewScreen focus={focus} />
        ) : route.name === "import" ? (
          <ImportScreen focus={focus} />
        ) : route.name === "data" ? (
          <DataScreen focus={focus} />
        ) : (
          <TransactionsScreen focus={focus} />
        )}
      </main>
    </>
  );
}
