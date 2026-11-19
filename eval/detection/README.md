# Recurring-charge detection eval

Measures how well `Detection::Engine` finds a household's subscriptions, their price increases and second subscriptions, without flagging anything else.

```sh
bin/rails 'leak:eval:detection[golden]'   # frozen set, aggregate scores only, enforces the gate (CI)
bin/rails 'leak:eval:detection[dev]'      # tuning set, lists every wrong or missed series, increase and duplicate
```

## Data

Everything here is **synthetic**. Real statements never enter git.

| file | households | transactions | use |
|---|---:|---:|---|
| `golden-v1.jsonl` | 100 | 50,218 | Frozen. CI gates on it. Never tune against its rows. |
| `dev.jsonl` | 60 | 31,277 | Tuning and error analysis. Regenerate freely. |

Each line is one household's history, 13 to 24 months of merchant transactions (rows that resolution already tied to a catalogue merchant; detection never sees people or unresolved rows):

```json
{"id":"h7-001","as_of":"2026-08-31",
 "txns":[[1,"swiggy","food_delivery","2024-11-01",-34900,null,"noise"],[2,"netflix","streaming","2024-11-05",-64900,"netflix-1","charge"],…],
 "series":{"netflix-1":{"merchant":"netflix","category":"streaming","cadence":"monthly","kind":"subscription","status":"active",
           "charges":18,"detectable":true,"increase":{"previous_amount_paise":49900,"txn":212},"duplicate_of":null},…}}
```

A transaction is `[id, merchant, category, date, signed paise, series key or null, role]`.
- Roles: `charge` (part of a series), `noise` (an ordinary purchase), `refund`, `mandate` (₹1/₹2 AutoPay set-ups and card verifications), `reversal` (a failed renewal debited and credited back), `trial` (a charge refunded in full).
- A series is a `subscription` (worth flagging) or a `commitment` (SIP, EMI, rent, insurance, utility bill, card bill: recurring, but not a leak).
- `detectable`: a subscription with at least three charges in the window (two if annual). Fewer can't be told from chance, so they count neither for nor against recall.
- `increase`: the first charge at a higher price, when a reader could see it (at least one charge before, and two at the new price).
- `duplicate_of`: for two subscriptions at one merchant, the one that appears first in the statement.

Histories come from `Synthetic::Histories` (`lib/synthetic/histories.rb`). It is built to be hard in the ways real statements are:
- charges land up to three days late and slip past weekends;
- renewals fail and a month is skipped;
- 28- and 84-day prepaid plans drift against the calendar;
- USD subscriptions move with the exchange rate every month;
- prices step up (sometimes by 5%), plans downgrade;
- second subscriptions start at the same merchant, at the same or a different price;
- subscriptions are cancelled;
- SIPs, rent and insurance step up yearly, and utility bills follow usage and the seasons;
- people order the same meal, take the same ride and top up the same fuel amount again and again;
- app stores mix subscriptions with in-app purchases at the same price points;
- Swiggy One sits among food orders;
- decoys: ₹1 mandates, repeated card verifications, reversed renewals, refunded trials, refunded orders.

## Metrics

- **False flags per 100 charges** (the headline): of all debits, how many the engine puts in a flagged series that are not charges of a real subscription.
- **Series precision / recall**: a flagged series is right when at least 80% of its charges belong to one real subscription that no other flagged series already claimed. Splitting one subscription in two costs precision.
- **Price increases**: matched by the exact transaction of the first charge at the new price, which is the evidence the UI will link to.
- **Duplicate subscriptions**: matched by the pair of series.
- **Status**: active vs ended, on matched series.

Intervals are 95% Wilson intervals. Charges cluster by household, so the intervals on charge counts are optimistic.

## Baseline and gate

On golden-v1 (2026-11-21):

| metric | value |
|---|---|
| False flags | **0.06 per 100 charges** [0.04, 0.08], 29 of 49,665 debits, all ordinary purchases |
| Series precision | 97.9% [95.8, 99.0] (331 of 338) |
| Series recall | 95.7% [93.0, 97.4] (of 346 detectable) |
| Price increases | precision 100% (47/47), recall 92.2% (47/51) |
| Duplicate subscriptions | precision 100% (22/22), recall 100% (22/22) |
| Status | 99.1% |

The gate (`config/eval.yml`) sits a little below every line, and flagging any commitment always fails.

Known misses (dev set): Swiggy One-style subscriptions sold by delivery apps, because merchants where people mostly buy things only get monthly series, and only exact, on-time ones; and app-store subscriptions with fewer than four charges.

**Synthetic numbers overstate real-world performance.** The generator and the engine were written by the same people, so the generator's idea of messy is the engine's idea of messy. The real test is the first real statements, read by hand.

### Golden set log

- **v1 (2026-11-21):** `leak:eval:generate_histories[eval/detection/golden-v1.jsonl,20261121,100]`.
  - **Not hand-reviewed row by row** (50,218 rows). Labels are the generator's ground truth. The labelling rules were checked against the dev set's error lists, and one was fixed there before freezing: which of two subscriptions counts as the duplicate now follows what the statement shows, not which one started first off-screen.
  - An earlier draft (seed 20261120) was used while the engine was being built. Only its aggregate scores were looked at. It was replaced by this fresh seed when the labelling changed. The new set was scored once, with the final engine, for the baseline above.
