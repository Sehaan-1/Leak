# Leak

Finds the subscriptions and recurring charges quietly draining a household's
bank account, from the statements the household already has.

Upload an SBI PDF statement and Leak shows what you pay every month for
subscriptions, which ones got more expensive, and where you're paying twice.
Every number traces back to the rows of the statement, and the merchant
matching and the detection are checked in CI against fixed synthetic test
sets.

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

Details: [docs/design/statement-import.md](docs/design/statement-import.md).

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

Details: [docs/design/rules-merchant-resolution.md](docs/design/rules-merchant-resolution.md).

### The LLM step

Rows the rules abstain on go to an LLM, after each import (a background job) or on demand. The LLM picks a catalogue merchant, `person` or `unknown`, and quotes its evidence. Validators then:
- check that the evidence is really in the narration;
- check that it matches the merchant's names better than any other merchant's;
- apply the rules' test for a personal name.

Anything else, including every `unknown`, stays in review with the reason. Details: [docs/design/llm-merchant-resolution.md](docs/design/llm-merchant-resolution.md).

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

**LLM eval.** CI replays recorded replies (`LLM_EVAL=replay`, offline) once recordings exist. On golden, rules + LLM must keep the 95% accuracy floor and beat rules only on net score (correct − 3 × wrong). [`llm-eval.yml`](.github/workflows/llm-eval.yml) runs the live model when the prompt, resolver or catalogue changes, nightly, and on demand (`record=true` commits fresh recordings). **Not yet enforced:** no provider secret is set, so the live eval is skipped and no recordings exist yet. To turn it on, add a `GEMINI_API_KEY` repository secret, then run `gh workflow run llm-eval.yml -f record=true`.

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

Details: [docs/design/recurring-charge-detection.md](docs/design/recurring-charge-detection.md).

## Stack

Ruby 4.0 · Rails 8.1 · PostgreSQL 18 · poppler (`pdftotext`) · RSpec · RuboCop (omakase) · Brakeman ·
bundler-audit · React 19 · TypeScript (strict) · Vite · TanStack Query · openapi-fetch · Vitest +
Testing Library + MSW · Biome · GitHub Actions.

The JSON API contract is [`openapi/openapi.yaml`](openapi/openapi.yaml).
Request specs validate every request and response against it (committee), and
a spec fails if a route under `/api` is added without documenting it. The web
client's types are generated from the same file (`npm --prefix web run api-types`),
and CI fails if the committed types are stale.

## Screens

- **Findings**: what the household pays each month for subscriptions, with price increases and second subscriptions first. "Mark as OK" hides a finding until something new happens.
- **Series**: every charge behind a finding, with the price over time.
- **Review**: the payees the resolvers wouldn't guess, grouped. One answer teaches Leak that payee for good ([details](docs/design/review-queue-and-dismissals.md)).
- **Import**: upload an SBI PDF statement; see past imports and why any were rejected.
- **Your data**: what Leak keeps, and **Delete my data**, which erases every statement, transaction and finding after a confirmation, and keeps you signed in ([details](docs/design/delete-my-data.md)).

## Running it locally (WSL2 / Linux / macOS)

Keep the repo on the Linux filesystem, not `/mnt/c`.

```sh
# Ruby 4.0.10 (see .ruby-version), PostgreSQL 18, poppler-utils (pdftotext), Node 22.12+
bin/setup              # gems, web/node_modules, database; then starts bin/dev
bin/rails db:seed      # synthetic demo household: demo@leak.test / demo-password-change-me
bin/dev                # Rails on :3000 and Vite on :5173 (--rails-only for Rails alone)
bin/ci                 # everything CI runs: rubocop, brakeman, audit, schema drift, rspec, evals, web checks
```

Open <http://localhost:5173> and sign in with the demo account, then import
`spec/fixtures/synthetic/sbi/sample_statement.pdf`. Rails renders the HTML
shell (so the CSRF token is in the page) and Vite serves the scripts with hot
reload, proxying everything else to Rails. Opening Vite through another
hostname (a VM, a tunnel) needs `VITE_ALLOWED_HOSTS=that.host`. To try the
production build, run `npm --prefix web run build` and `bin/dev --rails-only`,
then open <http://localhost:3000>. `LEAK_DEMO=1 bin/dev` runs it as the public demo.

Frontend checks: `npm --prefix web run lint`, `typecheck`, `test`, and
`npm --prefix web run e2e` (Playwright; starts Rails in the test environment
on a seeded database).

## Deploying

Two instances from one image with [Kamal 2](https://kamal-deploy.org), usually on one VPS ([details](docs/design/deploy-and-public-demo.md)):

| Destination | What it is |
|---|---|
| `demo` | Public. "Try it with made-up data" gives each visitor a household of synthetic data, deleted after 24 hours. **Uploads are off.** |
| `private` | The household's real statements. No sign-up: you create the accounts. |

Each has its own Postgres 18 (a Kamal accessory), its own secrets and its own domain, with TLS from Let's Encrypt via kamal-proxy.

**1. A server.** Any VPS with Docker-compatible Linux, ports 22, 80 and 443 open, and SSH access (root, or set `LEAK_SSH_USER`). Point the domains' DNS at it.

**2. Settings**, as environment variables where you run Kamal, or as repository secrets for the `Deploy` workflow:

| Variable | |
|---|---|
| `LEAK_SERVER` | the VPS's IP address or hostname |
| `LEAK_DEMO_HOST`, `LEAK_PRIVATE_HOST` | the domains, e.g. `demo.example.com` |
| `KAMAL_REGISTRY_USERNAME`, `KAMAL_REGISTRY_PASSWORD` | your GitHub user and a token with `write:packages` (the image goes to `ghcr.io/<user>/leak`). The workflow uses its own token. |
| `LEAK_<DESTINATION>_*` | secrets: `bin/rails 'leak:secrets[demo]'` and `bin/rails 'leak:secrets[private]'` print a fresh set (`SECRET_KEY_BASE`, the three Active Record Encryption keys, `POSTGRES_PASSWORD`) |
| `LEAK_PRIVATE_LLM_PROVIDER`, `_API_KEY`, `_MODEL`, `_BASE_URL` | optional, [the LLM step](#the-llm-step) on the private instance; leave empty to skip it |
| `SSH_PRIVATE_KEY` | workflow only: a key the server accepts |

Keep the generated secrets somewhere safe (a password manager). **Losing the Active Record Encryption keys makes the stored narrations unreadable.** [`.kamal/secrets.<destination>`](.kamal) only names the variables, so nothing secret is in git.

Email (optional; Leak only sends password-reset mail): add `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME` and `MAIL_FROM` to a destination's `env.clear`, and `SMTP_PASSWORD` to its `env.secret` and `.kamal/secrets.<destination>`. Without it, reset a password with `leak:users:password`.

**3. Deploy:**

```sh
bin/kamal setup -d demo        # first time: Docker, kamal-proxy, Postgres, app
bin/kamal setup -d private
bin/kamal deploy -d private    # afterwards
# or from GitHub: gh workflow run deploy.yml -f destination=private [-f setup=true]
```

The container prepares the database and loads the merchant catalogue on boot, and refuses to boot without its secrets.

**4. Accounts on the private instance:**

```sh
# The inner quotes reach the server's shell (Kamal joins the command into one string).
bin/kamal rails -d private "'leak:users:create[mum@example.com,Sharma household]'"  # prints a password once
bin/kamal rails -d private "'leak:users:password[mum@example.com]'"                 # new password, signs out everywhere
bin/kamal rails -d private "'leak:users:delete[mum@example.com]'" CONFIRM=yes       # the household and everything in it
bin/kamal console -d private
```

CI builds the production image on every push and boots it as the demo against Postgres (the `image` job, [`script/smoke-test-image`](script/smoke-test-image)).

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
- The public demo can't receive a statement: uploads are refused there, and
  each visitor's synthetic household is deleted after 24 hours.
- **Delete my data** on the "Your data" screen erases every statement,
  transaction and finding for the household, at once.
- Secrets (`config/*.key`, credentials) are never committed; production
  secrets are supplied at deploy time.

## Design notes

Why things are the way they are, in [`docs/design/`](docs/design):

- [Money is integer paise](docs/design/integer-paise.md)
- [Double-entry ledger with database-enforced invariants](docs/design/double-entry-ledger.md)
- [Same-origin cookie sessions, not JWT](docs/design/cookie-session-auth.md)
- [OpenAPI file as the API contract](docs/design/openapi-contract.md)
- [Statement import: exact parsing, reconciliation, fingerprints](docs/design/statement-import.md)
- [The SPA is served by Rails, built by Vite](docs/design/spa-served-by-rails.md)
- [Rules-first merchant resolution, measured on a frozen synthetic set](docs/design/rules-merchant-resolution.md)
- [LLM merchant resolution: any provider, grounded answers, replayed in CI](docs/design/llm-merchant-resolution.md)
- [Recurring-charge detection: explainable chains, decoys rejected by rule, measured by false flags](docs/design/recurring-charge-detection.md)
- [Review queue answers teach the resolver; dismissals are anchored on ledger rows](docs/design/review-queue-and-dismissals.md)
- [Two Kamal instances from one image; the public demo can't take real statements](docs/design/deploy-and-public-demo.md)
- ["Delete my data" erases everything in one transaction and keeps the sign-in](docs/design/delete-my-data.md)

## Not built yet

- Undoing a review answer.
- Statements from banks other than SBI.
- The live LLM eval gate: it switches on when a provider key is added (see
  [The LLM step](#the-llm-step)).
