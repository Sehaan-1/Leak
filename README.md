# Leak

Finds the subscriptions and recurring charges quietly draining a household's
bank account, from the statements the household already has.

Built for one real user (an SBI account holder) and evaluated like a product:
every number on the dashboard traces back to ledger rows, and the merchant
resolver and the detection engine are gated in CI against frozen synthetic
golden sets.

> **Status: slice 6 of the build.** A double-entry ledger whose invariants
> are enforced by PostgreSQL, SBI PDF statement import that only accepts
> statements that reconcile to the paisa, a bare React app to sign in,
> upload a statement and list its transactions, a rules merchant resolver
> with an eval gate in CI, an LLM resolver (any provider) for what the
> rules can't decide, behind validators, and a detection engine that finds
> subscriptions, price increases and second subscriptions, gated in CI on
> false flags. The real screens come next (see [Roadmap](#roadmap)).

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

Or upload it in the web app, or `POST /api/v1/statement_imports` with a `file` (multipart).

## Merchant resolution

```text
narration ──parse (UPI / NEFT / IMPS / card / NACH / bill)──▶ rules ──▶ merchant | person | bank | cash
                                                                 └──▶ abstain ──▶ LLM ──▶ validators ──▶ merchant | person
                                                                                                    └──▶ review
```

- The catalogue is [`config/merchants.yml`](config/merchants.yml): about 55 Indian merchants with names, UPI IDs and categories. SIPs, EMIs, insurance, rent and utilities are categorised, so detection can treat them as decoys.
- Rules run strongest first: exact UPI ID; payee name (exact, prefix, or truncated); UPI ID before the `@`; catalogue names in card/NACH text; then a `pg_trgm` match only when one merchant clearly wins. If the signals disagree, it abstains.
- Each transaction stores which rule decided, so every merchant can be traced to its evidence.

**Eval** ([details](eval/merchant_resolution/README.md)): all synthetic. The golden set is 300 rows, reviewed and frozen; the dev set is 600 rows. The rules-only baseline on golden is **99.4% merchant accuracy [96.8–99.9%] at 76.3% coverage**. CI fails below 95% (lower bound) or 75% coverage. Synthetic numbers overstate real-world accuracy.

Details: [ADR 7](docs/adr/0007-rules-merchant-resolution.md).

### The LLM step

Rows the rules abstain on go to an LLM, after each import (a background job) or on demand. The LLM picks a catalogue merchant, `person` or `unknown`, and quotes its evidence. Validators then:
- check that the evidence is really in the narration;
- check that it matches the merchant's names better than any other merchant's;
- apply the rules' test for a personal name.

Anything else, including every `unknown`, stays in review with the reason. Details: [ADR 8](docs/adr/0008-llm-merchant-resolution.md).

**Choose any provider** ([`config/llm.yml`](config/llm.yml)). Keys go in the environment or `bin/rails credentials:edit` (`llm: { provider:, api_key:, model:, base_url: }`), never in git.

| You have | Set |
|---|---|
| Any OpenAI-compatible API | `LLM_BASE_URL`, `LLM_MODEL`, `LLM_API_KEY` |
| A preset | `LLM_PROVIDER=gemini\|nvidia\|openai\|openrouter\|groq\|ollama` + its key (`LLM_MODEL` optional) |
| Antigravity or opencode installed and logged in | nothing: they are used automatically (`agy -p`, `opencode run`) |
| Only a free key | `GEMINI_API_KEY` (aistudio.google.com) or `NVIDIA_API_KEY` (build.nvidia.com) |
| Nothing | the LLM step is skipped and abstentions go to review |

The order when you set nothing explicit is: an installed agent, then Gemini, then NVIDIA. Digit runs (references, account and phone numbers) are masked before anything is sent, and prompts and replies are never logged. Payee names are still sent, and free tiers may train on what they receive. **For real statements, use a paid tier, a local model (`ollama`) or your own agent.**

```sh
bin/rails leak:merchants:sync                          # load the catalogue (db:seed does this too)
bin/rails 'leak:merchants:resolve[demo@leak.test]'     # rules on unresolved rows (ALL=1 to redo)
bin/rails leak:llm:check                               # which provider is used; one synthetic test call
bin/rails 'leak:merchants:llm[demo@leak.test]'         # send rows in review to the LLM now
bin/rails 'leak:eval:merchants[golden]'                # gated eval; [dev] lists every miss
LLM_EVAL=record LLM_PROVIDER=gemini bin/rails 'leak:eval:merchants[golden]'   # live eval, saves replay recordings
```

**LLM eval.** PR CI replays recorded replies (`LLM_EVAL=replay`, offline). On golden, rules + LLM must keep the 95% accuracy floor and beat rules only on net score (correct − 3 × wrong). [`llm-eval.yml`](.github/workflows/llm-eval.yml) runs the live model on PRs that touch the prompt, resolver or catalogue, nightly, and on demand (`record=true` commits fresh recordings). **Not yet enforced:** no provider secret is set, so the live eval is skipped and no recordings exist yet. To turn it on, add a `GEMINI_API_KEY` repository secret, then run `gh workflow run llm-eval.yml -f record=true`.

## Detection

```text
merchant rows ──drop ₹1 mandates and refunded charges──▶ chains per merchant + cadence ──▶ series (price levels)
                                                                                         ├──▶ commitments: SIP, EMI, rent, insurance, utilities, card bills (never flagged)
                                                                                         └──▶ findings: subscription | price_increase | duplicate
```

- A chain repeatedly takes the charge closest to where the next one is due (±5 days monthly, one missed period allowed), at the same price. Rupee prices must repeat exactly; USD prices may drift 6% per charge.
- A new price where the next charge was due, confirmed by a second charge, is a **price step**. A new price that was already being charged alongside is a **second subscription**.
- Chains that the merchant's other same-price purchases could form by chance are rejected (the commute fare, the usual meal). Merchants where people mostly buy things need four exact, on-time monthly charges.
- Every series is a list of ledger rows, and every price increase points at the first charge at the new price.
- It runs after every import, and again after the LLM resolves rows. All thresholds are in [`config/detection.yml`](config/detection.yml).

**Eval** ([details](eval/detection/README.md)): synthetic household histories with ground truth, full of decoys. The golden set is 100 households (50k transactions) and frozen; the dev set is 60 households. Baseline on golden: **0.06 false flags per 100 charges [0.04–0.08]**, series precision 97.9%, recall 95.7%, price increases 100% precision / 92% recall, duplicates 100% / 100%. CI gates every one of these, and flagging any commitment fails.

```sh
bin/rails 'leak:detect[demo@leak.test]'      # rebuild a household's series and findings
bin/rails 'leak:eval:detection[golden]'      # gated eval; [dev] lists every miss
```

Details: [ADR 9](docs/adr/0009-recurring-charge-detection.md).

## Stack

Ruby 4.0 · Rails 8.1 · PostgreSQL 18 · poppler (`pdftotext`) · RSpec · RuboCop (omakase) · Brakeman ·
bundler-audit · React 19 · TypeScript (strict) · Vite · TanStack Query · openapi-fetch · Vitest +
Testing Library + MSW · Biome · GitHub Actions.

The JSON API contract is [`openapi/openapi.yaml`](openapi/openapi.yaml).
Request specs validate every request and response against it (committee), and
a spec fails if a route under `/api` is added without documenting it. The web
client's types are generated from the same file (`npm --prefix web run api-types`),
and CI fails if the committed types are stale.

## Running it locally (WSL2 / Linux / macOS)

Keep the repo on the Linux filesystem, not `/mnt/c`.

```sh
# Ruby 4.0.10 (see .ruby-version), PostgreSQL 18, and poppler-utils (pdftotext)
bin/setup              # installs gems, prepares the database, starts the server
bin/rails db:seed      # synthetic demo household: demo@leak.test / demo-password-change-me
bin/ci                 # everything CI runs: rubocop, brakeman, audit, schema drift, rspec, web checks

# Node 22.12+ for the React app in web/
npm --prefix web ci
npm --prefix web run dev   # Vite on :5173, proxying everything else to Rails on :3000
```

Open <http://localhost:5173> and sign in with the demo account, then import
`spec/fixtures/synthetic/sbi/sample_statement.pdf`. Rails renders the HTML
shell (so the CSRF token is in the page) and Vite serves the scripts with hot
reload. To try the production build instead, run `npm --prefix web run build`
and open <http://localhost:3000> with `VITE_DEV_SERVER=0 bin/rails server`.

Frontend checks: `npm --prefix web run lint`, `typecheck`, `test`.

## Privacy rules

- Real statements never enter git, fixtures, screenshots or LLM logs. The
  LLM resolver masks digit runs before sending, and never logs prompts or
  replies. Replay recordings are made from the synthetic eval sets only.
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
6. [The SPA is served by Rails, built by Vite](docs/adr/0006-spa-served-by-rails.md)
7. [Rules-first merchant resolution, measured on a frozen synthetic set](docs/adr/0007-rules-merchant-resolution.md)
8. [LLM merchant resolution: any provider, grounded answers, replayed in CI](docs/adr/0008-llm-merchant-resolution.md)
9. [Recurring-charge detection: explainable chains, decoys rejected by rule, measured by false flags](docs/adr/0009-recurring-charge-detection.md)

## Roadmap

One slice per PR, each leaving something demoable.

1. **Foundation**: app, auth, ledger + invariants, CI.
2. **SBI PDF statement import**: `pdftotext -layout` parser,
   reconciliation, idempotent fingerprints, import-twice and
   overlapping-import property tests.
3. **Bare React list**: Vite + TS SPA served by Rails, types generated from
   OpenAPI; sign in, upload a statement, list transactions.
4. **Alias table + rules resolver, synthetic generator, eval harness,
   baseline in CI**.
5. **LLM resolver behind the router**, validators, replay fixtures, the eval
   gate.
6. **Detection engine**: cadence fitting, price steps, decoys, false-flag
   gate ← you are here.
7. **The four screens** and the Playwright test.
8. **Deploy** (Kamal 2): public synthetic demo + private instance.
