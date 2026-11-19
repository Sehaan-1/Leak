# Merchant resolution eval

Measures how well Leak turns a bank narration into a counterparty: a merchant from the catalogue (`config/merchants.yml`), a person, the bank itself, cash, or an abstention, which sends the row to review.

```sh
bin/rails 'leak:eval:merchants[golden]'   # frozen set, aggregate scores only, enforces the gate (CI)
bin/rails 'leak:eval:merchants[dev]'      # tuning set, lists every wrong answer and abstention
```

## Data

Everything here is **synthetic**. Real statements never enter git.

| file | rows | use |
|---|---:|---|
| `golden-v1.jsonl` | 300 | Frozen. CI gates on it. Never tune rules against its rows. |
| `dev.jsonl` | 600 | Tuning and error analysis. Regenerate freely. |

Each line looks like this:

```json
{"id":"s1-0001","narration":"TO TRANSFER-UPI/DR/…/SWIGGY L/ICIC/swiggy.stor/Payment fo--","amount_paise":-34900,"label":"swiggy","channel":"upi_merchant","noise":["payee truncated","UPI ID truncated"]}
```

`label` is a catalogue slug, `unknown` (a real business missing from the catalogue), `person`, `bank` or `cash`.

Rows come from `Synthetic::Narrations` (`lib/synthetic/narrations.rb`). Its surface forms are written independently of the catalogue, and some are deliberately absent from it:
- legal names;
- aggregator UPI IDs;
- abbreviations.

On top of that, the generator damages narrations the way real statements do:
- payee names and UPI IDs truncated, sometimes losing the `@domain`;
- mixed case;
- the fixed-width wrap that puts spaces inside words.

Some rows are impossible to resolve on purpose:
- payments that show only the gateway ("RAZORPAY");
- unknown shops whose names resemble catalogue merchants;
- shops paid through personal-looking UPI IDs.

Labels come from the generator's ground truth. The golden rows were then read one by one before freezing, and any corrections are listed below.

### Golden set review log

- **v1 (2026-11-20):** generated with `leak:eval:generate[eval/merchant_resolution/golden-v1.jsonl,20261119,300]`. All 300 rows were read before freezing, before any resolver output on them had been seen.
  - **Corrections:** none.
  - **Hard but correct labels:**
    - `…-011` "JIO WORLD" and `…-146` "JIO WORLD DRIVE PARKING" are a mall, not Jio telecom → `unknown`.
    - `…-250` "OLA ELECTRIC SERVICE CENTRE" is not Ola cabs → `unknown`.
    - `…-270` "NEW BOMB" is a truncated shop name → `unknown`.
    - The 3% `upi_gateway` rows carry the true merchant, which the text can't reveal, so the only right answer is to abstain.

## Metrics

Over rows whose true counterparty is a business (a catalogue slug or `unknown`):

- **coverage** = answered ÷ business rows. Abstaining is allowed.
- **merchant accuracy** = correct ÷ answered. Answering wrongly is not allowed. An `unknown` row can only be answered wrongly.

Both come with 95% Wilson score intervals. With 300 rows, ±2 points is noise. The report also gives:
- catalogue recall, i.e. the share of catalogue-merchant rows named correctly;
- overall accuracy and coverage including person, bank and cash rows;
- per-channel counts.

The gate (`config/eval.yml`) requires the Wilson **lower bound** of merchant accuracy, and the coverage, to stay at or above the stated values. It is a regression guard for the rules-only baseline. Slice 5's LLM resolver must beat it on the same set.

## Changing the golden set

Don't edit `golden-v1.jsonl`: its SHA-256 is pinned in `config/eval.yml`, and specs fail when it changes. To change it:
1. Generate `golden-v2.jsonl` with a new seed.
2. Review it.
3. Point `config/eval.yml` at it with its hash.
4. Add a line to the review log above explaining why.

## Limits

Synthetic narrations are cleaner and less varied than real ones, so these numbers **overstate** real-world accuracy. Treat them as a regression baseline, not a promise. The real test is the first real statement, checked through the review queue.
