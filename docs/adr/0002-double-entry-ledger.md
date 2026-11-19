# 2. Double-entry ledger with database-enforced invariants

**Status:** accepted

## Context

Imports will be re-run, overlap, and be corrected. Findings must link back to
the transactions behind them. A single-entry "transactions" table makes it
easy to double-count or silently lose a row, and retrofitting double-entry
later is worse than starting with it.

## Decision

- Tables: `households`, `accounts`, `journal_entries`, `postings`. Each
  posting carries `household_id`; composite foreign keys tie it to an account
  and an entry of the same household.
- Positive amounts are debits, negative are credits. An entry's postings sum
  to zero.
- The chart of accounts stays tiny: one asset account per bank account, one
  expense account per merchant, an equity account for opening balances, and
  one suspense account per household for unknown counterparties.
- The balance rule is a `DEFERRABLE INITIALLY DEFERRED` constraint trigger,
  so an entry can be built across several `INSERT`s and is checked once at
  `COMMIT`. Postings are append-only; mistakes are fixed with reversing
  entries.
- `Ledger.post!` validates in Ruby first for good error messages. The
  database is the backstop.
- The schema is dumped as `structure.sql` so triggers are versioned.

## Consequences

- No code path, including raw SQL from a console, can commit an unbalanced
  ledger.
- Transactional specs never commit, so they force deferred checks with
  `SET CONSTRAINTS ALL IMMEDIATE`; one non-transactional spec proves the
  real `COMMIT` behaviour.
- Deleting a household cascades through the whole ledger cleanly, which is
  the basis of "delete my data".
