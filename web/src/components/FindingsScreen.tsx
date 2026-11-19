import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRef, useState } from "react";
import { type Finding, type FindingsList, listFindings, setFindingDismissed } from "../api/client";
import { formatPlainDate } from "../lib/dates";
import { formatRupees } from "../lib/money";
import { href } from "../lib/router";
import { CADENCE_LABEL, CADENCE_PHRASE, formatMonth } from "../lib/series";
import { useTitle } from "../lib/title";
import { PageHeading } from "./Heading";

function seriesHref(id: number) {
  return href({ name: "series", id });
}

/** One sentence on what was found, in rupees and dates. */
export function findingText(finding: Finding): string {
  const { series } = finding;
  switch (finding.kind) {
    case "price_increase": {
      const previous = finding.previous_amount_paise ?? 0;
      const when = finding.step_charge ? ` on ${formatPlainDate(finding.step_charge.posted_on)}` : "";
      return (
        `Price went up from ${formatRupees(previous)} to ${formatRupees(finding.amount_paise)}${when}. ` +
        `That's ${formatRupees(finding.amount_paise - previous)} more ${CADENCE_PHRASE[series.cadence]}.`
      );
    }
    case "duplicate": {
      const first = finding.related_series;
      const alongside = first
        ? `, alongside the one at ${formatRupees(first.amount_paise)} since ${formatMonth(first.first_charged_on)}`
        : "";
      return (
        `A second ${series.merchant.name} subscription: ${formatRupees(finding.amount_paise)} ` +
        `${CADENCE_PHRASE[series.cadence]} since ${formatMonth(series.first_charged_on)}${alongside}.`
      );
    }
    case "subscription":
      return `${formatRupees(finding.amount_paise)} ${CADENCE_PHRASE[series.cadence]}.`;
  }
}

const TITLE: Record<Finding["kind"], string> = {
  price_increase: "price went up",
  duplicate: "second subscription",
  subscription: "subscription",
};

function FindingCard({
  finding,
  onToggle,
  pending,
}: {
  finding: Finding;
  onToggle: (finding: Finding) => void;
  pending: boolean;
}) {
  const { series } = finding;
  const headingId = `finding-${finding.id}`;
  return (
    <article className={`card finding finding-${finding.kind}`} aria-labelledby={headingId}>
      <h3 id={headingId}>
        <a href={seriesHref(series.id)}>{series.merchant.name}</a>
        <span className="tag">{TITLE[finding.kind]}</span>
      </h3>
      <div>
        <p>{findingText(finding)}</p>
        <p className="hint">
          {series.charges_count} charges since {formatPlainDate(series.first_charged_on)}, last on{" "}
          {formatPlainDate(series.last_charged_on)}.
          {finding.related_series && (
            <>
              {" "}
              <a href={seriesHref(finding.related_series.id)}>See the first subscription's charges</a>
            </>
          )}
        </p>
      </div>
      <footer>
        <button type="button" className="secondary" onClick={() => onToggle(finding)} disabled={pending}>
          {finding.dismissed ? "Show again" : "Mark as OK"}
          <span className="visually-hidden">
            : {series.merchant.name} {TITLE[finding.kind]}
          </span>
        </button>
      </footer>
    </article>
  );
}

function SubscriptionsTable({ findings }: { findings: Finding[] }) {
  return (
    // biome-ignore lint/a11y/noNoninteractiveTabindex: a scrollable region must be keyboard-scrollable
    <section className="table-wrapper" aria-labelledby="subscriptions-caption" tabIndex={0}>
      <table className="subscriptions">
        <caption id="subscriptions-caption">Active subscriptions, most expensive first</caption>
        <thead>
          <tr>
            <th scope="col">Merchant</th>
            <th scope="col">How often</th>
            <th scope="col" className="num">
              Price
            </th>
            <th scope="col" className="num">
              Per month
            </th>
            <th scope="col">Next charge</th>
          </tr>
        </thead>
        <tbody>
          {findings.map(({ id, series, amount_paise, monthly_cost_paise }) => (
            <tr key={id}>
              <th scope="row">
                <a href={seriesHref(series.id)}>{series.merchant.name}</a>
              </th>
              <td>{CADENCE_LABEL[series.cadence]}</td>
              <td className="num">{formatRupees(amount_paise)}</td>
              <td className="num">{formatRupees(monthly_cost_paise)}</td>
              <td>{formatPlainDate(series.next_expected_on)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}

export function FindingsScreen({ focus, reviewCount }: { focus: boolean; reviewCount: number }) {
  useTitle("Findings");
  const queryClient = useQueryClient();
  const query = useQuery({ queryKey: ["findings"], queryFn: listFindings });
  const attentionHeading = useRef<HTMLHeadingElement>(null);
  const [announcement, setAnnouncement] = useState("");

  const toggle = useMutation({
    mutationFn: (finding: Finding) => setFindingDismissed(finding.id, !finding.dismissed),
    onSuccess: (updated) => {
      queryClient.setQueryData<FindingsList>(
        ["findings"],
        (list) =>
          list && { ...list, findings: list.findings.map((f) => (f.id === updated.id ? updated : f)) },
      );
      queryClient.invalidateQueries({ queryKey: ["recurring_series"] });
      const name = `${updated.series.merchant.name} ${TITLE[updated.kind]}`;
      setAnnouncement(updated.dismissed ? `${name} marked as OK.` : `${name} moved back to Needs a look.`);
      // The button that had focus has moved to the other list.
      attentionHeading.current?.focus();
    },
  });

  const findings = query.data?.findings ?? [];
  const flagged = findings.filter((f) => f.kind !== "subscription");
  const attention = flagged.filter((f) => !f.dismissed);
  const dismissed = flagged.filter((f) => f.dismissed);
  const subscriptions = findings.filter((f) => f.kind === "subscription" && f.series.status === "active");

  return (
    <>
      <PageHeading focus={focus}>Your subscriptions</PageHeading>
      {query.isPending ? (
        <p role="status">Loading findings…</p>
      ) : query.isError ? (
        <div role="alert">
          <p>Couldn't load findings. {query.error.message}</p>
          <button type="button" onClick={() => query.refetch()}>
            Try again
          </button>
        </div>
      ) : findings.length === 0 ? (
        <p>
          No subscriptions found yet. <a href={href({ name: "import" })}>Import a statement</a> with a few
          months of transactions and Leak will look for charges that repeat.
        </p>
      ) : (
        <>
          <p className="summary">
            You pay <strong>{formatRupees(query.data.monthly_total_paise)} a month</strong> for{" "}
            {query.data.subscriptions_count === 1
              ? "1 subscription"
              : `${query.data.subscriptions_count} subscriptions`}
            .
          </p>
          {reviewCount > 0 && (
            <p className="result result-info">
              {reviewCount === 1 ? "1 payment needs" : `${reviewCount} payments need`} your help before Leak
              can tell who they were to. <a href={href({ name: "review" })}>Review them</a>
            </p>
          )}

          <section aria-labelledby="attention-heading">
            <h2 id="attention-heading" ref={attentionHeading} tabIndex={-1}>
              Needs a look
            </h2>
            {attention.length === 0 ? (
              <p>Nothing right now. No price rises or second subscriptions.</p>
            ) : (
              <div className="cards">
                {attention.map((f) => (
                  <FindingCard
                    key={f.id}
                    finding={f}
                    onToggle={toggle.mutate}
                    pending={toggle.isPending && toggle.variables?.id === f.id}
                  />
                ))}
              </div>
            )}
          </section>

          <section aria-labelledby="subscriptions-heading">
            <h2 id="subscriptions-heading">All subscriptions</h2>
            {subscriptions.length === 0 ? (
              <p>No active subscriptions.</p>
            ) : (
              <SubscriptionsTable findings={subscriptions} />
            )}
          </section>

          {dismissed.length > 0 && (
            <section aria-labelledby="dismissed-heading">
              <h2 id="dismissed-heading">Marked as OK</h2>
              <div className="cards">
                {dismissed.map((f) => (
                  <FindingCard
                    key={f.id}
                    finding={f}
                    onToggle={toggle.mutate}
                    pending={toggle.isPending && toggle.variables?.id === f.id}
                  />
                ))}
              </div>
            </section>
          )}
          {toggle.isError && (
            <p role="alert" className="result result-problem">
              Couldn't save that. {toggle.error.message}
            </p>
          )}
        </>
      )}
      <p role="status" className="visually-hidden">
        {announcement}
      </p>
    </>
  );
}
