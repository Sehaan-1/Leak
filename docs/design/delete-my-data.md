# "Delete my data" erases everything in one transaction and keeps the sign-in

## Problem

The household's statements are the most sensitive thing Leak holds. The user must be able to see what is kept and remove it, without asking anyone. The ledger makes deletion harder than usual: postings are append-only (`postings_append_only` trigger), balances are checked by a deferred trigger, and most tables carry composite foreign keys to the household's accounts (see [ledger](double-entry-ledger.md)).

## Approach

- **A "Your data" screen** lists what Leak keeps (statements, transactions, subscriptions found, payees named in Review, findings marked as OK) from `GET /api/v1/household_data`, and says what it doesn't keep: uploaded PDFs are never stored (see [statement import](statement-import.md)).
- **"Delete my data…"** opens a native modal `<dialog>` that states what will go. The safe button ("Keep my data") has focus, so Enter or Esc keeps the data; only "Delete everything" sends `DELETE /api/v1/household_data`.
- **`Household#erase_data!`** deletes, in one transaction and in dependency order, the household's finding dismissals, findings, series, journal entries (postings and bank transactions cascade), statement imports, bank accounts, accounts and learned merchant aliases. It returns the counts it deleted, which the screen reports.
  - Deleting is allowed by the ledger: the append-only trigger only rejects updates, and the deferred balance check skips entries that no longer exist.
  - The merchant catalogue is shared and never touched.
- **The household, its users and their sessions stay.** The user is still signed in on an empty household and can import again. Deleting the account itself is a server task (`leak:users:delete[email] CONFIRM=yes`), and demo households are deleted whole by `Demo::CleanupJob`; both use `Household#destroy` with the same ordered associations.

## Trade-offs

- One click and one confirmation removes everything; there is no undo and no soft delete, so nothing lingers.
- Database backups (if the operator takes them) still contain the data until they rotate. Narrations in them are encrypted (see [statement import](statement-import.md)), but the keys are on the same server.
- Every screen's cached data is invalidated after deletion, so nothing deleted stays on screen.
- A test checks that a destroyed household leaves no rows in any of the eleven household tables.

## Not chosen

- **Delete the account too:** the household's only user would be signed out with no way back in on the private instance, where accounts are created by the operator.
- **Rely on `ON DELETE CASCADE` from `households`:** it only fires when the household row itself goes, which is not what this button does, and the composite foreign keys to `accounts` aren't cascading.
- **A typed confirmation ("type DELETE"):** heavier than the decision warrants for a household app with one or two users; the dialog's default is already the safe choice.
