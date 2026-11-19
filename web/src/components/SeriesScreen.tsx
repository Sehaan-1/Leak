import { useQuery } from "@tanstack/react-query";
import { lazy, Suspense } from "react";
import { ApiError, getSeries, type SeriesDetail } from "../api/client";
import { formatPlainDate } from "../lib/dates";
import { formatRupees } from "../lib/money";
import { href } from "../lib/router";
import { CADENCE_PHRASE } from "../lib/series";
import { useTitle } from "../lib/title";
import { findingText } from "./FindingsScreen";
import { PageHeading } from "./Heading";

// Recharts is most of the app's JavaScript; only this screen needs it.
const SeriesChart = lazy(() => import("./SeriesChart"));

const back = (
  <p className="back">
    <a href={href({ name: "findings" })}>
      <span aria-hidden="true">← </span>All subscriptions
    </a>
  </p>
);

function Facts({ series }: { series: SeriesDetail }) {
  return (
    <dl className="facts">
      <div>
        <dt>Price now</dt>
        <dd>
          {formatRupees(series.amount_paise)} {CADENCE_PHRASE[series.cadence]}
        </dd>
      </div>
      <div>
        <dt>Per month</dt>
        <dd>{formatRupees(series.monthly_cost_paise)}</dd>
      </div>
      <div>
        <dt>Charges</dt>
        <dd>
          {series.charges_count} since {formatPlainDate(series.first_charged_on)}
        </dd>
      </div>
      <div>
        <dt>{series.status === "active" ? "Next charge expected" : "Ended"}</dt>
        <dd>
          {series.status === "active"
            ? formatPlainDate(series.next_expected_on)
            : `last charged ${formatPlainDate(series.last_charged_on)}`}
        </dd>
      </div>
    </dl>
  );
}

function ChargesTable({ series }: { series: SeriesDetail }) {
  return (
    // biome-ignore lint/a11y/noNoninteractiveTabindex: a scrollable region must be keyboard-scrollable
    <section className="table-wrapper" aria-labelledby="charges-caption" tabIndex={0}>
      <table className="charges">
        <caption id="charges-caption">Every {series.merchant.name} charge, oldest first</caption>
        <thead>
          <tr>
            <th scope="col">Date</th>
            <th scope="col" className="num">
              Charged
            </th>
            <th scope="col">Details</th>
          </tr>
        </thead>
        <tbody>
          {series.charges.map((charge) => (
            <tr
              key={charge.id}
              id={`charge-${charge.id}`}
              className={charge.price_step ? "price-step" : undefined}
            >
              <th scope="row">{formatPlainDate(charge.posted_on)}</th>
              <td className="num">
                {formatRupees(charge.charged_paise)}
                {charge.price_step && <strong className="tag tag-step">New price</strong>}
              </td>
              <td className="details">{charge.narration}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}

export function SeriesScreen({ id, focus }: { id: number; focus: boolean }) {
  const query = useQuery({ queryKey: ["recurring_series", id], queryFn: () => getSeries(id) });
  useTitle(query.data?.merchant.name ?? "Charges");

  if (query.isPending) {
    return (
      <>
        {back}
        <p role="status">Loading charges…</p>
      </>
    );
  }
  if (query.isError) {
    const gone = query.error instanceof ApiError && query.error.status === 404;
    return (
      <>
        {back}
        <PageHeading focus={focus}>
          {gone ? "These charges have moved" : "Couldn't load these charges"}
        </PageHeading>
        {gone ? (
          <p>
            Leak recalculated your subscriptions since this page was opened.{" "}
            <a href={href({ name: "findings" })}>Go back to your subscriptions</a> and open it again.
          </p>
        ) : (
          <div role="alert">
            <p>{query.error.message}</p>
            <button type="button" onClick={() => query.refetch()}>
              Try again
            </button>
          </div>
        )}
      </>
    );
  }

  const series = query.data;
  const step = series.charges.find((charge) => charge.price_step);
  return (
    <>
      {back}
      <PageHeading focus={focus}>{series.merchant.name}</PageHeading>
      <Facts series={series} />
      {series.findings
        .filter((finding) => finding.kind !== "subscription")
        .map((finding) => (
          <div key={finding.id} className={`result ${finding.dismissed ? "result-info" : "result-problem"}`}>
            <p>
              {findingText(finding)}
              {finding.kind === "price_increase" && step && (
                <>
                  {" "}
                  <button type="button" className="link-button" onClick={() => jumpTo(`charge-${step.id}`)}>
                    Show the first charge at the new price
                  </button>
                </>
              )}
              {finding.related_series && (
                <>
                  {" "}
                  <a href={href({ name: "series", id: finding.related_series.id })}>
                    See the other subscription
                  </a>
                </>
              )}
              {finding.dismissed && " You marked this as OK."}
            </p>
          </div>
        ))}
      {!series.flagged && (
        <p className="hint">
          This looks like a commitment (a bill, loan, insurance or investment), so Leak doesn't flag it.
        </p>
      )}

      <section aria-labelledby="chart-heading">
        <h2 id="chart-heading">What each charge cost</h2>
        <figure className="chart-figure">
          <Suspense fallback={<div className="chart" />}>
            <SeriesChart charges={series.charges} />
          </Suspense>
          <figcaption className="hint">
            One bar per charge.
            {step
              ? ` The red bar on ${formatPlainDate(step.posted_on)} is the first charge at the new price.`
              : " The price hasn't changed."}{" "}
            The table below lists every charge.
          </figcaption>
        </figure>
      </section>

      <section aria-labelledby="charges-heading">
        <h2 id="charges-heading">Charges</h2>
        <ChargesTable series={series} />
      </section>
    </>
  );
}

// Scrolls to a row and focuses it. Not a #fragment link: the hash is the
// app's route.
function jumpTo(id: string) {
  const row = document.getElementById(id);
  if (!row) return;
  row.setAttribute("tabindex", "-1");
  row.focus({ preventScroll: true });
  row.scrollIntoView?.({ block: "center" });
}
