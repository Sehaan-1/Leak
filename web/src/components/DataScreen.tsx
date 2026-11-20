import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { type SyntheticEvent, useEffect, useRef, useState } from "react";
import { type DataCounts, deleteHouseholdData, getHouseholdData } from "../api/client";
import { formatInstant } from "../lib/dates";
import { useTitle } from "../lib/title";
import { PageHeading } from "./Heading";

const ROWS: { key: keyof DataCounts; label: string }[] = [
  { key: "statements", label: "Statements imported" },
  { key: "transactions", label: "Transactions" },
  { key: "subscriptions", label: "Subscriptions found" },
  { key: "learned_merchants", label: "Payees you named in Review" },
  { key: "dismissed_findings", label: "Findings marked as OK" },
];

function markAutofocus(button: HTMLButtonElement | null) {
  button?.setAttribute("autofocus", "");
}

function plural(count: number, one: string, many = `${one}s`): string {
  return `${count.toLocaleString("en-IN")} ${count === 1 ? one : many}`;
}

function deletedText(deleted: DataCounts): string {
  if (deleted.statements === 0 && deleted.transactions === 0) {
    return "Done. There was nothing to delete, and Leak now holds no data of yours.";
  }
  return `Deleted ${plural(deleted.statements, "statement")} and ${plural(deleted.transactions, "transaction")}. Leak now holds no data of yours.`;
}

/**
 * "Your data": what Leak keeps for the household, and "Delete my data",
 * confirmed in a native modal <dialog>. The sign-in stays.
 */
export function DataScreen({ focus }: { focus: boolean }) {
  useTitle("Your data");
  const queryClient = useQueryClient();
  const query = useQuery({ queryKey: ["household_data"], queryFn: getHouseholdData });
  const dialogRef = useRef<HTMLDialogElement>(null);
  const resultRef = useRef<HTMLDivElement>(null);
  const [result, setResult] = useState<{ text: string } | null>(null);

  const mutation = useMutation({
    mutationFn: deleteHouseholdData,
    onSuccess: (deleted) => {
      setResult({ text: deletedText(deleted) });
      // Every screen's data is gone; the signed-in user ("me") isn't.
      void queryClient.invalidateQueries({ predicate: (q) => q.queryKey[0] !== "me" });
    },
  });

  // Focus the outcome so it is read out, as the dialog hands focus back.
  useEffect(() => {
    if (result) resultRef.current?.focus();
  }, [result]);

  function onClose(event: SyntheticEvent<HTMLDialogElement>) {
    const dialog = event.currentTarget;
    const choice = dialog.returnValue;
    // Esc sets no value, and browsers differ on clearing the last one.
    dialog.returnValue = "";
    if (choice === "delete") {
      setResult(null);
      mutation.mutate();
    }
  }

  const counts = query.data?.counts;
  const demoExpiresAt = query.data?.demo_expires_at;

  return (
    <>
      <PageHeading focus={focus}>Your data</PageHeading>
      {demoExpiresAt && (
        <p className="result result-info">
          This is a demo account with made-up data. Leak deletes it on {formatInstant(demoExpiresAt)}.
        </p>
      )}

      <section aria-labelledby="kept-heading">
        <h2 id="kept-heading">What Leak keeps</h2>
        {query.isPending ? (
          <p role="status">Loading…</p>
        ) : query.isError ? (
          <div role="alert">
            <p>Couldn't load what Leak keeps. {query.error.message}</p>
            <button type="button" onClick={() => query.refetch()}>
              Try again
            </button>
          </div>
        ) : (
          <dl className="facts">
            {ROWS.map((row) => (
              <div key={row.key}>
                <dt>{row.label}</dt>
                <dd>{query.data.counts[row.key].toLocaleString("en-IN")}</dd>
              </div>
            ))}
          </dl>
        )}
        <p>
          Leak doesn't keep the statement files you upload: it reads them and throws them away. It keeps the
          transactions, with each payment's details encrypted, the last four digits of the account number, and
          what you tell it in Review.
        </p>
      </section>

      <section aria-labelledby="delete-heading">
        <h2 id="delete-heading">Delete my data</h2>
        <p>
          This deletes every statement, transaction and finding, and everything you told Leak in Review. You
          stay signed in, and you can import statements again afterwards. It can't be undone.
        </p>
        <button
          type="button"
          className="danger"
          onClick={() => dialogRef.current?.showModal()}
          disabled={mutation.isPending}
        >
          {mutation.isPending ? "Deleting…" : "Delete my data…"}
        </button>

        {/* Always in the page, so filling it in is announced. */}
        <div role="alert" className="form-error">
          {mutation.isError && `Nothing was deleted. ${mutation.error.message}`}
        </div>
        {result && (
          <div className="result result-ok" ref={resultRef} tabIndex={-1}>
            <p>
              <span aria-hidden="true">✓ </span>
              {result.text}
            </p>
          </div>
        )}

        <dialog ref={dialogRef} aria-labelledby="confirm-delete-title" onClose={onClose}>
          <h2 id="confirm-delete-title">Delete all your data?</h2>
          <p>
            {counts
              ? `${plural(counts.statements, "statement")} and ${plural(counts.transactions, "transaction")} will be deleted, with everything Leak found in them.`
              : "Every statement and transaction will be deleted, with everything Leak found in them."}{" "}
            This can't be undone.
          </p>
          <form method="dialog" className="dialog-actions">
            {/* The safe choice takes focus when the dialog opens, so Enter keeps the data.
                The attribute itself, for showModal() to find: React's autoFocus prop only
                focuses on mount and leaves no attribute. */}
            <button type="submit" value="keep" className="secondary" ref={markAutofocus}>
              Keep my data
            </button>
            <button type="submit" value="delete" className="danger">
              Delete everything
            </button>
          </form>
        </dialog>
      </section>
    </>
  );
}
