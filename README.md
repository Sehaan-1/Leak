# Leak

Finds the subscriptions and recurring charges quietly draining a household's
bank account, from the statements the household already has.

Built for one real user (an SBI account holder) and evaluated like a product:
every number on the dashboard traces back to ledger rows, and the merchant
resolver is gated in CI against a hand-labelled golden set.

> **Status: slice 2 of the build.** A double-entry ledger whose invariants
> are enforced by PostgreSQL, and SBI PDF statement import that only accepts
> statements that reconcile to the paisa. Merchant resolution, detection and
> the dashboard come in later slices (see [Roadmap](#roadmap)).

## Ledger invariants

Money is `bigint` paise. Every write goes through a double-entry journal, and
PostgreSQL rejects anything that would break these rules, even raw SQL from
a console:

| Invariant | Enforced by |
|---|---|
| Every journal entry's postings sum to exactly zero | Deferred constraint trigger, checked at `COMMIT` |
| No empty entries, no single-leg entries | Same trigger plus one on `journal_entries` |
| A posting only references accounts and entries of its own household | Composite foreign keys `(id, household_id)` |
| Amounts are non-zero integers | `bigint` column + `CHECK (amount_paise <> 0)` |
| Postings are append-only; corrections are reversing entries | `BEFORE UPDATE` trigger |
| One suspense account per household | Partial unique index |

The schema lives in [`db/structure.sql`](db/structure.sql) (not `schema.rb`)
so triggers are versioned, and CI fails if it drifts from the migrations.
Specs in [`spec/db/`](spec/db) attack each rule with raw SQL, and one spec
really commits to prove the check runs at `COMMIT`.

## Statement import

```text
PDF ──pdftotext -layout──▶ text ──SBI parser──▶ rows ──reconcile──▶ ledger
                                                    │
                                     doesn't tie? reject, with the exact row
```

- Amounts, dates and balances come from a per-bank parser, never an LLM.
- A statement is imported only if every running balance ties and the last
  balance matches the printed closing balance. Otherwise nothing is written
  and the import records the row that failed.
- Re-uploads and overlapping statements are idempotent: each line has a
  fingerprint unique per household, and importing statements in any order
  produces the same ledger.
- The PDF is not stored. Narrations are encrypted at rest, and only the
  account number's last four digits are kept.

Details: [ADR 5](docs/adr/0005-statement-import.md).

```sh
bin/rails 'leak:import[path/to/statement.pdf,demo@leak.test]'   # PDF_PASSWORD=... if protected
bin/rails 'leak:redact[path/to/statement.pdf]'                  # shape-only copy, safe to share in a bug report
```

Or `POST /api/v1/statement_imports` with a `file` (multipart).

## Stack

Ruby 4.0 · Rails 8.1 · PostgreSQL 18 · poppler (`pdftotext`) · RSpec · RuboCop (omakase) · Brakeman ·
bundler-audit · GitHub Actions. React + TypeScript arrives in a later slice.

The JSON API contract is [`openapi/openapi.yaml`](openapi/openapi.yaml).
Request specs validate every request and response against it (committee), and
a spec fails if a route under `/api` is added without documenting it.

## Running it locally (WSL2 / Linux / macOS)

Keep the repo on the Linux filesystem, not `/mnt/c`.

```sh
# Ruby 4.0.10 (see .ruby-version), PostgreSQL 18, and poppler-utils (pdftotext)
bin/setup              # installs gems, prepares the database, starts the server
bin/rails db:seed      # synthetic demo household: demo@leak.test / demo-password-change-me
bin/ci                 # everything CI runs: rubocop, brakeman, audit, schema drift, rspec
```

Then open <http://localhost:3000> and sign in with the demo account. The
JSON API (`/api/v1/session`, `/me`, `/accounts`, `/statement_imports`) is for
the SPA that arrives in slice 3. Writes need the CSRF token from the page, so the
request specs in [`spec/requests/`](spec/requests) are the best usage examples.

## Privacy rules

- Real statements never enter git, fixtures, screenshots or LLM logs.
  `.gitignore` blocks `*.pdf`, `*.csv`, `*.xls*` and `*.eml` outside
  `spec/fixtures/synthetic/`.
- Seeds and the public demo use synthetic data only. The SBI fixture is a
  fabricated statement; other test statements are generated
  (`spec/support/synthetic_sbi.rb`).
- Uploaded PDFs are not stored. Narrations and references are encrypted at
  rest (Active Record Encryption).
- Secrets (`config/*.key`, credentials) are never committed; production
  secrets are supplied at deploy time.

## Decisions

Short ADRs live in [`docs/adr/`](docs/adr):

1. [Money is integer paise](docs/adr/0001-integer-paise.md)
2. [Double-entry ledger with database-enforced invariants](docs/adr/0002-double-entry-ledger.md)
3. [Same-origin cookie sessions, not JWT](docs/adr/0003-cookie-session-auth.md)
4. [OpenAPI file as the API contract](docs/adr/0004-openapi-contract.md)
5. [Statement import: exact parsing, reconciliation, fingerprints](docs/adr/0005-statement-import.md)

## Roadmap

One slice per PR, each leaving something demoable.

1. **Foundation**: app, auth, ledger + invariants, CI.
2. **SBI PDF statement import** ← you are here: `pdftotext -layout` parser,
   reconciliation, idempotent fingerprints, import-twice and
   overlapping-import property tests.
3. **Bare React list**: Vite + TS SPA served by Rails, types generated from OpenAPI.
4. **Alias table + rules resolver, synthetic generator, eval harness, baseline in CI.**
5. **LLM resolver behind the router**, validators, replay fixtures, the eval gate.
6. **Detection engine**: cadence fitting, price steps, decoys.
7. **The four screens** and the Playwright test.
8. **Deploy** (Kamal 2): public synthetic demo + private instance.
