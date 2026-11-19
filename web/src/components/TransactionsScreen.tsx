import { useTitle } from "../lib/title";
import { PageHeading } from "./Heading";
import { TransactionsTable } from "./TransactionsTable";

export function TransactionsScreen({ focus }: { focus: boolean }) {
  useTitle("Transactions");
  return (
    <>
      <PageHeading focus={focus}>Transactions</PageHeading>
      <TransactionsTable />
    </>
  );
}
