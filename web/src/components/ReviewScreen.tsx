import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { type FormEvent, useEffect, useId, useRef, useState } from "react";
import {
  type Answer,
  listMerchants,
  listReviewItems,
  type Merchant,
  type Resolution,
  type ReviewItem,
  resolveReviewItem,
} from "../api/client";
import { formatPlainDate } from "../lib/dates";
import { formatSignedRupees } from "../lib/money";
import { useTitle } from "../lib/title";
import { PageHeading } from "./Heading";

/** Rows with the same UPI ID (or payee) are one question: answering it once answers them all. */
type Group = { key: string; items: ReviewItem[] };

function groupItems(items: ReviewItem[]): Group[] {
  const groups = new Map<string, ReviewItem[]>();
  for (const item of items) {
    const key = item.upi_id ?? item.payee ?? `row-${item.id}`;
    groups.set(key, [...(groups.get(key) ?? []), item]);
  }
  return [...groups].map(([key, rows]) => ({ key, items: rows }));
}

const OTHERS: { value: string; label: string }[] = [
  { value: "person", label: "A person (family, friend, someone I paid)" },
  { value: "bank", label: "The bank (a fee, charge or interest)" },
  { value: "cash", label: "Cash" },
];

function toAnswer(value: string): Answer | null {
  if (value === "person" || value === "bank" || value === "cash") return { counterparty: value };
  const id = Number(value.replace(/^merchant-/, ""));
  return value.startsWith("merchant-") && Number.isSafeInteger(id)
    ? { counterparty: "merchant", merchant_id: id }
    : null;
}

/** Answers every row in the group: one request for a merchant (the server learns it), one per row otherwise. */
async function answerGroup(group: Group, answer: Answer): Promise<Resolution> {
  const [first, ...rest] = group.items as [ReviewItem, ...ReviewItem[]];
  const result = await resolveReviewItem(first.id, answer);
  if (answer.counterparty !== "merchant") {
    for (const item of rest) await resolveReviewItem(item.id, answer);
  }
  return result;
}

function confirmation(group: Group, answer: Answer, result: Resolution): string {
  const count = group.items.length === 1 ? "1 payment" : `${group.items.length} payments`;
  if (result.merchant) {
    const learned = result.learned ? ` Leak will recognise ${result.learned.pattern} from now on.` : "";
    return `Saved: ${count} to ${result.merchant.name}.${learned}`;
  }
  const who = OTHERS.find((other) => other.value === answer.counterparty)?.label.split(" (")[0] ?? "";
  return `Saved: ${count} marked as ${who.toLowerCase()}.`;
}

function ReviewCard({
  group,
  merchants,
  onSaved,
}: {
  group: Group;
  merchants: Merchant[];
  onSaved: (message: string) => void;
}) {
  const queryClient = useQueryClient();
  const id = useId();
  const [choice, setChoice] = useState("");
  const latest = group.items[0] as ReviewItem;
  const total = group.items.reduce((sum, item) => sum + item.amount_paise, 0);

  const mutation = useMutation({
    mutationFn: (answer: Answer) => answerGroup(group, answer),
    onSuccess: async (result, answer) => {
      onSaved(confirmation(group, answer, result));
      await Promise.all(
        ["review_items", "findings", "bank_transactions", "recurring_series"].map((key) =>
          queryClient.invalidateQueries({ queryKey: [key] }),
        ),
      );
    },
  });

  function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const answer = toAnswer(choice);
    if (answer) mutation.mutate(answer);
  }

  const title = latest.payee ?? "Unknown payee";
  return (
    <article className="card review" aria-labelledby={`${id}-title`}>
      <h2 id={`${id}-title`}>{title}</h2>
      <dl className="facts compact">
        <div>
          <dt>{group.items.length === 1 ? "Payment" : "Payments"}</dt>
          <dd>
            {group.items.length === 1
              ? `${formatSignedRupees(latest.amount_paise)} on ${formatPlainDate(latest.posted_on)}`
              : `${group.items.length}, latest ${formatSignedRupees(latest.amount_paise)} on ${formatPlainDate(latest.posted_on)} (${formatSignedRupees(total)} in all)`}
          </dd>
        </div>
        {latest.upi_id && (
          <div>
            <dt>UPI ID</dt>
            <dd className="details">{latest.upi_id}</dd>
          </div>
        )}
        {latest.reason && (
          <div>
            <dt>Why Leak asks</dt>
            <dd>{latest.reason}</dd>
          </div>
        )}
        <div>
          <dt>On the statement</dt>
          <dd className="details">{latest.narration}</dd>
        </div>
      </dl>
      <form onSubmit={onSubmit} aria-labelledby={`${id}-title`}>
        <div className="field">
          <label htmlFor={`${id}-who`}>Who was this?</label>
          <select
            id={`${id}-who`}
            value={choice}
            onChange={(event) => setChoice(event.target.value)}
            required
            aria-describedby={mutation.isError ? `${id}-error` : undefined}
          >
            <option value="">Choose…</option>
            <optgroup label="Not a business">
              {OTHERS.map((other) => (
                <option key={other.value} value={other.value}>
                  {other.label}
                </option>
              ))}
            </optgroup>
            <optgroup label="Businesses">
              {merchants.map((merchant) => (
                <option key={merchant.id} value={`merchant-${merchant.id}`}>
                  {merchant.name}
                </option>
              ))}
            </optgroup>
          </select>
        </div>
        <button type="submit" disabled={mutation.isPending || choice === ""}>
          {mutation.isPending ? "Saving…" : "Save"}
        </button>
        {mutation.isError && (
          <p id={`${id}-error`} role="alert" className="result result-problem">
            Couldn't save. {mutation.error.message}
          </p>
        )}
      </form>
    </article>
  );
}

export function ReviewScreen({ focus }: { focus: boolean }) {
  useTitle("Review");
  const review = useQuery({ queryKey: ["review_items"], queryFn: listReviewItems });
  const merchants = useQuery({
    queryKey: ["merchants"],
    queryFn: listMerchants,
    staleTime: Number.POSITIVE_INFINITY,
  });
  const [saved, setSaved] = useState<{ text: string } | null>(null);
  const savedRef = useRef<HTMLDivElement>(null);
  // The answered card goes away with the focused Save button in it, so move
  // focus to the confirmation, which reads it out.
  useEffect(() => {
    if (saved) savedRef.current?.focus();
  }, [saved]);

  const groups = groupItems(review.data?.review_items ?? []);
  const shown = review.data?.review_items.length ?? 0;
  const total = review.data?.total_count ?? 0;

  return (
    <>
      <PageHeading focus={focus}>Who were these payments to?</PageHeading>
      <p>
        Leak couldn't tell who these payments went to or came from. Tell it once: it remembers the UPI ID or
        name for next time, and looks for subscriptions again.
      </p>
      {saved && (
        <div className="result result-ok" ref={savedRef} tabIndex={-1}>
          <p>
            <span aria-hidden="true">✓ </span>
            {saved.text}
          </p>
        </div>
      )}
      {review.isPending || merchants.isPending ? (
        <p role="status">Loading…</p>
      ) : review.isError || merchants.isError ? (
        <div role="alert">
          <p>Couldn't load the payments to review. {(review.error ?? merchants.error)?.message}</p>
          <button
            type="button"
            onClick={() => {
              review.refetch();
              merchants.refetch();
            }}
          >
            Try again
          </button>
        </div>
      ) : groups.length === 0 ? (
        <p>Nothing to review. Leak knows who every payment went to.</p>
      ) : (
        <>
          <p className="hint">
            {total === 1 ? "1 payment" : `${total} payments`} to review
            {shown < total ? ` (showing the newest ${shown})` : ""}.
          </p>
          <div className="cards">
            {groups.map((group) => (
              <ReviewCard
                key={group.key}
                group={group}
                merchants={merchants.data}
                onSaved={(text) => setSaved({ text })}
              />
            ))}
          </div>
        </>
      )}
    </>
  );
}
