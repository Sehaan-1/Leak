# Leak

Finds the subscriptions and recurring charges quietly draining a household's
bank account, from the statements the household already has.

Built for one real user (an SBI account holder) and evaluated like a product:
every number on the dashboard traces back to ledger rows, and the merchant
resolver is gated in CI against a hand-labelled golden set.

> **Status: slice 1 of the build (foundation).** Rails app, authentication,
> and a double-entry ledger whose invariants are enforced by PostgreSQL.
> Statement import, merchant resolution, detection and the dashboard come in
> later slices (see [Roadmap](#roadmap)).

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

## Stack

Ruby 4.0 · Rails 8.1 · PostgreSQL 18 · RSpec · RuboCop (omakase) · Brakeman ·
bundler-audit · GitHub Actions. React + TypeScript arrives in a later slice.

The JSON API contract is [`openapi/openapi.yaml`](openapi/openapi.yaml).
Request specs validate every request and response against it (committee), and
a spec fails if a route under `/api` is added without documenting it.

## Running it locally (WSL2 / Linux / macOS)

Keep the repo on the Linux filesystem, not `/mnt/c`.

```sh
# Ruby 4.0.10 (see .ruby-version) and PostgreSQL 18 running locally
bin/setup              # installs gems, prepares the database, starts the server
bin/rails db:seed      # synthetic demo household: demo@leak.test / demo-password-change-me
bin/ci                 # everything CI runs: rubocop, brakeman, audit, schema drift, rspec
```

Then open <http://localhost:3000> and sign in with the demo account. The
JSON API (`/api/v1/session`, `/api/v1/me`, `/api/v1/accounts`) is for the SPA
that arrives in slice 3. Writes need the CSRF token from the page, so the
request specs in [`spec/requests/`](spec/requests) are the best usage examples.

## Privacy rules

- Real statements never enter git, fixtures, screenshots or LLM logs.
  `.gitignore` blocks `*.pdf`, `*.csv`, `*.xls*` and `*.eml` outside
  `spec/fixtures/synthetic/`.
- Seeds and the public demo use synthetic data only.
- Secrets (`config/*.key`, credentials) are never committed; production
  secrets are supplied at deploy time.

## Decisions

Short ADRs live in [`docs/adr/`](docs/adr):

1. [Money is integer paise](docs/adr/0001-integer-paise.md)
2. [Double-entry ledger with database-enforced invariants](docs/adr/0002-double-entry-ledger.md)
3. [Same-origin cookie sessions, not JWT](docs/adr/0003-cookie-session-auth.md)
4. [OpenAPI file as the API contract](docs/adr/0004-openapi-contract.md)

## Roadmap

One slice per PR, each leaving something demoable.

1. **Foundation** ← you are here: app, auth, ledger + invariants, CI.
2. **SBI PDF statement import**: `pdftotext -layout` parser, reconciliation
   (opening + movements = closing, row-by-row running balance), idempotent
   fingerprints, import-twice and overlapping-import property tests.
3. **Bare React list**: Vite + TS SPA served by Rails, types generated from OpenAPI.
4. **Alias table + rules resolver, synthetic generator, eval harness, baseline in CI.**
5. **LLM resolver behind the router**, validators, replay fixtures, the eval gate.
6. **Detection engine**: cadence fitting, price steps, decoys.
7. **The four screens** and the Playwright test.
8. **Deploy** (Kamal 2): public synthetic demo + private instance.
