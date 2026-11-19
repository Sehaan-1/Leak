import { useMutation, useQueryClient } from "@tanstack/react-query";
import { type Me, signOut } from "../api/client";
import { PageHeading } from "./Heading";
import { TransactionsTable } from "./TransactionsTable";
import { UploadStatement } from "./UploadStatement";

export function Dashboard({ me, focusHeading }: { me: Me; focusHeading: boolean }) {
  const queryClient = useQueryClient();
  const signOutMutation = useMutation({
    mutationFn: signOut,
    // App swaps to sign-in and then drops this household's cached data.
    onSuccess: () => queryClient.setQueryData(["me"], null),
  });

  return (
    <>
      <header className="topbar">
        <p className="brand">Leak</p>
        <p className="who">
          Signed in as <strong>{me.user.email_address}</strong>
        </p>
        <button
          type="button"
          className="secondary"
          onClick={() => signOutMutation.mutate()}
          disabled={signOutMutation.isPending}
        >
          Sign out
        </button>
      </header>
      <main className="page">
        <PageHeading focus={focusHeading}>{me.household.name}</PageHeading>
        <UploadStatement />
        <TransactionsTable />
      </main>
    </>
  );
}
