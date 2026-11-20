import { useQuery } from "@tanstack/react-query";
import { isDemoInstance, listStatementImports } from "../api/client";
import { formatPlainDate } from "../lib/dates";
import { useTitle } from "../lib/title";
import { PageHeading } from "./Heading";
import { UploadStatement } from "./UploadStatement";

function ImportsList() {
  const query = useQuery({ queryKey: ["statement_imports"], queryFn: listStatementImports });

  return (
    <section aria-labelledby="imports-heading">
      <h2 id="imports-heading">Imported statements</h2>
      {query.isPending ? (
        <p role="status">Loading statements…</p>
      ) : query.isError ? (
        <div role="alert">
          <p>Couldn't load your statements. {query.error.message}</p>
          <button type="button" onClick={() => query.refetch()}>
            Try again
          </button>
        </div>
      ) : query.data.length === 0 ? (
        <p>None yet.</p>
      ) : (
        // biome-ignore lint/a11y/noNoninteractiveTabindex: a scrollable region must be keyboard-scrollable
        <section className="table-wrapper" aria-labelledby="imports-caption" tabIndex={0}>
          <table className="imports">
            <caption id="imports-caption">Statements you've imported, latest first</caption>
            <thead>
              <tr>
                <th scope="col">File</th>
                <th scope="col">Account</th>
                <th scope="col">Period</th>
                <th scope="col">Result</th>
              </tr>
            </thead>
            <tbody>
              {query.data.map((s) => (
                <tr key={s.id}>
                  <th scope="row" className="details">
                    {s.filename}
                  </th>
                  <td>{s.bank_account?.name ?? "—"}</td>
                  <td>
                    {s.period_from && s.period_to
                      ? `${formatPlainDate(s.period_from)} to ${formatPlainDate(s.period_to)}`
                      : "—"}
                  </td>
                  <td>
                    {s.status === "imported"
                      ? `Imported ${s.new_rows_count} new of ${s.rows_count} transactions`
                      : `Rejected: ${s.error?.message ?? "unknown error"}`}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}
    </section>
  );
}

export function ImportScreen({ focus }: { focus: boolean }) {
  useTitle("Statements");
  return (
    <>
      <PageHeading focus={focus}>Statements</PageHeading>
      {isDemoInstance() ? (
        <p className="result result-info">
          This public demo only uses made-up data, so uploading statements is turned off. A year of a made-up
          SBI statement has been imported for you.
        </p>
      ) : (
        <UploadStatement />
      )}
      <ImportsList />
    </>
  );
}
