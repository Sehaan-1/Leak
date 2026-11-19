import { useInfiniteQuery } from "@tanstack/react-query";
import { listTransactions } from "../api/client";
import { formatPlainDate } from "../lib/dates";
import { formatRupees, formatSignedRupees } from "../lib/money";

export function TransactionsTable() {
  const query = useInfiniteQuery({
    queryKey: ["bank_transactions"],
    queryFn: ({ pageParam }) => listTransactions(pageParam),
    initialPageParam: 1,
    getNextPageParam: (last) => last.next_page ?? undefined,
  });

  const rows = query.data?.pages.flatMap((page) => page.bank_transactions) ?? [];

  return (
    <section aria-labelledby="transactions-heading">
      <h2 id="transactions-heading">Transactions</h2>
      {query.isPending ? (
        <p role="status">Loading transactions…</p>
      ) : query.isError ? (
        <div role="alert">
          <p>Couldn't load transactions. {query.error.message}</p>
          <button type="button" onClick={() => query.refetch()}>
            Try again
          </button>
        </div>
      ) : rows.length === 0 ? (
        <p>No transactions yet. Import a statement to see them here.</p>
      ) : (
        <>
          {/* A named <section> is a region landmark. tabIndex lets keyboard users scroll it. */}
          {/* biome-ignore lint/a11y/noNoninteractiveTabindex: a scrollable region must be keyboard-scrollable */}
          <section className="table-wrapper" aria-labelledby="transactions-caption" tabIndex={0}>
            <table>
              <caption id="transactions-caption">Bank transactions, newest first</caption>
              <thead>
                <tr>
                  <th scope="col">Date</th>
                  <th scope="col">Details</th>
                  <th scope="col" className="num">
                    Amount
                  </th>
                  <th scope="col" className="num">
                    Balance
                  </th>
                </tr>
              </thead>
              <tbody>
                {rows.map((t) => (
                  <tr key={t.id}>
                    <th scope="row">{formatPlainDate(t.posted_on)}</th>
                    <td className="details">{t.narration}</td>
                    <td className={`num ${t.amount_paise > 0 ? "money-in" : "money-out"}`}>
                      <span className="visually-hidden">
                        {t.amount_paise > 0 ? "Money in: " : "Money out: "}
                      </span>
                      {formatSignedRupees(t.amount_paise)}
                    </td>
                    <td className="num">{formatRupees(t.balance_after_paise)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </section>
          <p className="table-footer">
            <span role="status">
              Showing {rows.length} {rows.length === 1 ? "transaction" : "transactions"}
              {query.hasNextPage ? "" : " (all of them)"}.
            </span>
            {query.hasNextPage && (
              <button
                type="button"
                className="secondary"
                onClick={() => query.fetchNextPage()}
                disabled={query.isFetchingNextPage}
              >
                {query.isFetchingNextPage ? "Loading…" : "Show older transactions"}
              </button>
            )}
          </p>
        </>
      )}
    </section>
  );
}
