import { useMutation, useQueryClient } from "@tanstack/react-query";
import { type FormEvent, useRef } from "react";
import { type UploadOutcome, uploadStatement } from "../api/client";
import { formatPlainDate } from "../lib/dates";
import { useFieldErrors } from "../lib/fieldErrors";
import { formatRupees } from "../lib/money";

function describeOutcome(outcome: UploadOutcome): { tone: "ok" | "info" | "problem"; text: string } {
  switch (outcome.kind) {
    case "imported": {
      const s = outcome.statement;
      const period =
        s.period_from && s.period_to
          ? ` for ${formatPlainDate(s.period_from)} to ${formatPlainDate(s.period_to)}`
          : "";
      const closing =
        s.closing_balance_paise === null ? "" : ` Closing balance ${formatRupees(s.closing_balance_paise)}.`;
      const added = s.new_rows_count === 1 ? "1 new transaction" : `${s.new_rows_count} new transactions`;
      return { tone: "ok", text: `Statement imported${period}: ${added}.${closing}` };
    }
    case "already_imported":
      return { tone: "info", text: "You've already imported this statement. Nothing changed." };
    case "rejected":
      return {
        tone: "problem",
        text: `Couldn't import this statement. ${outcome.message} Nothing was added.`,
      };
  }
}

export function UploadStatement() {
  const queryClient = useQueryClient();
  const formRef = useRef<HTMLFormElement>(null);
  const fileRef = useRef<HTMLInputElement>(null);
  useFieldErrors(formRef);

  const mutation = useMutation({
    mutationFn: uploadStatement,
    onSuccess: (outcome) => {
      if (outcome.kind === "rejected") return;
      formRef.current?.reset();
      // Merchants are resolved during the import; detection follows in the
      // background, so findings may take a moment to catch up.
      return Promise.all(
        ["bank_transactions", "statement_imports", "review_items", "findings"].map((key) =>
          queryClient.invalidateQueries({ queryKey: [key] }),
        ),
      );
    },
  });

  function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const file = fileRef.current?.files?.[0];
    if (file) mutation.mutate(file);
  }

  const result = mutation.isSuccess
    ? describeOutcome(mutation.data)
    : mutation.isError
      ? { tone: "problem" as const, text: `Upload failed. ${mutation.error.message}` }
      : null;

  return (
    <section aria-labelledby="upload-heading">
      <h2 id="upload-heading">Import a statement</h2>
      <form
        ref={formRef}
        aria-labelledby="upload-heading"
        method="post"
        action="/api/v1/statement_imports"
        encType="multipart/form-data"
        onSubmit={onSubmit}
      >
        <div className="field">
          <label htmlFor="statement-file">SBI account statement (PDF)</label>
          <p id="statement-file-hint" className="hint">
            Download it from YONO SBI or OnlineSBI. Leak reads the PDF once and doesn't keep it.
          </p>
          <input
            ref={fileRef}
            id="statement-file"
            name="file"
            type="file"
            accept=".pdf,application/pdf"
            required
            aria-describedby="statement-file-hint"
            data-error="statement-file-error"
          />
          <p id="statement-file-error" className="error-msg">
            <span aria-hidden="true">⚠ </span>Choose your statement PDF first.
          </p>
        </div>
        <button type="submit" disabled={mutation.isPending}>
          {mutation.isPending ? "Importing…" : "Import statement"}
        </button>
      </form>
      {/* Always in the page, so a new result is announced politely. */}
      <div role="status" className={`result ${result ? `result-${result.tone}` : ""}`}>
        {result && (
          <p>
            <span aria-hidden="true">
              {result.tone === "ok" ? "✓ " : result.tone === "problem" ? "⚠ " : "ℹ "}
            </span>
            {result.text}
          </p>
        )}
      </div>
    </section>
  );
}
