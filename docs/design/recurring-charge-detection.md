# Recurring-charge detection: explainable chains, decoys rejected by rule, measured by false flags

## Problem

The point of Leak is to show a household its subscriptions, what they cost, when one got more expensive and when it is paying twice. A false flag ("this is a subscription" when it is the usual Friday dinner) costs trust the product can't buy back, so the main metric is **false flags per 100 charges**, not recall.

Statements are messy in ways that defeat a simple "same merchant, same amount, every month" rule:
- charges land a few days late, slip past weekends, and skip a month when a renewal fails;
- 28-day prepaid plans drift against the calendar;
- USD subscriptions change in rupees every month;
- prices step up, so the amount changes while the subscription doesn't;
- a second subscription at the same merchant looks like a price change if you squint;
- many things recur without being leaks: SIPs, EMIs, rent, insurance, utility bills (usage-priced), card bills;
- ₹1 AutoPay mandate set-ups, reversed renewals and refunded trials look like charges;
- people buy the same thing at the same price over and over: the commute fare, the usual meal, ₹500 of fuel, ₹99 in-app purchases.

Every finding has to be explainable on the screen: "these charges, this cadence, this is the charge where the price went up".

## Approach

- **Input:** only rows that merchant resolution tied to a catalogue merchant (see [rules resolver](rules-merchant-resolution.md) and [LLM resolver](llm-merchant-resolution.md)). People, bank charges and rows in review are ignored. A wrong merchant would merge or split series, which is why resolution abstains instead of guessing.
- **Clean-up first:** debits of ₹2 or less are mandates and verifications. A credit at the same merchant for exactly a charge's amount within 45 days refunds that charge, and neither counts.
- **Chains, not clustering.** Per merchant and cadence (monthly, then quarterly, half-yearly, annual, weekly), a chain starts at the earliest unclaimed charge and repeatedly takes the charge closest to where the next one is due:
  - within the cadence's tolerance (±5 days monthly), relative to the previous charge, so 28-day plans and late charges follow naturally;
  - allowing one missed period;
  - at the same price. A price that has repeated exactly must stay exact (a ₹189 → ₹199 rise is a step). A price that has been moving may drift 6% per charge (USD).
  - Three charges make a series (two for annual, four for weekly). Each charge belongs to at most one series.
- **Price step vs second subscription.** When the next charge at the same price doesn't come, a charge where it was due at 0.5–4× the price, followed by another at the new price, is a price step: a new level of the same series. It is not a step if the new price was already being charged a period earlier while the old one ran: that is a second subscription, found as its own chain. Two flagged, active series at one merchant produce a **duplicate** finding on the later one.
- **Coincidence test.** Repeated purchases at one price can line up by chance. With λ the daily rate of the merchant's other charges at that price, each step lands in its window w by chance with p = 1 − e^(−λw). A chain is coincidence if the expected number of such chains, seeds × Πp, reaches 0.001. With no other same-price charges it always passes, so ordinary subscriptions are untouched.
- **Merchants where people mostly buy things** (food delivery, groceries, shopping, transport, fuel, travel, pharmacy, wallets) also need four exact, on-time (±3 days), monthly charges, with no steps. **App stores** need four exact monthly charges, but keep the usual tolerance and steps.
- **Commitments** (investment, loan, insurance, rent, utilities, credit card categories) still become series, but are never flagged. Detection reports recurrence and change, not usage.
- **Status:** a series is active if its last charge is within one period plus tolerance of the household's latest transaction, so an old statement still shows what was active then.
- **Findings,** for active flagged series only:
  - `subscription`, with its monthly cost;
  - `price_increase`, linking the first charge at the new price and the old price;
  - `duplicate`, linking the other series.
- **Storage:** `recurring_series`, `recurring_series_charges` (each ledger row in at most one series, with its price level) and `findings`, with composite household foreign keys and check constraints for each finding kind's evidence. `Detection::Run` rebuilds them for a household after every import and after the LLM resolves rows (a background job), and `leak:detect` does it by hand. All thresholds are in `config/detection.yml`.
- **Evaluation** (`eval/detection/`): synthetic household histories with ground truth from `Synthetic::Histories`, a frozen 100-household golden set and a 60-household dev set. Metrics: false flags per 100 charges, series precision and recall, price increase and duplicate precision and recall, status accuracy, with Wilson intervals. CI gates all of them, and flagging any commitment fails.

## Trade-offs

- Baseline on golden-v1: **0.06 false flags per 100 charges** [0.04, 0.08], series precision 97.9%, recall 95.7%, price increases 100% / 92%, duplicates 100% / 100%.
- Every series is a list of ledger rows, and every price increase points at one, so the screens can show the evidence directly.
- The engine is plain Ruby over plain values: the eval runs it without a database, and Run is a thin persistence layer.
- Known misses: subscriptions sold by delivery apps (Swiggy One) and short app-store subscriptions. Any recurring purchase pattern at a non-commitment merchant that is regular enough is flagged by design.
- Rebuilding every run throws away anything attached to a series id, so what the user says about a finding has to be anchored elsewhere ([review queue](review-queue-and-dismissals.md)).
- The generator and engine were written together and share assumptions, so synthetic scores are an upper bound. Real statements, read by hand, are the next test.

## Not chosen

- **Amount-band clustering then period estimation** (FFT or median gap): it can't follow price steps or FX drift without wide bands, and wide bands merge a ₹199 plan with a ₹149 one at the same merchant. It also explains itself poorly.
- **An LLM deciding what is a subscription:** not reproducible, hard to evaluate, and it would need whole histories sent out. The LLM stays limited to naming merchants.
- **A fixed "crowded" rule** (reject a chain when the merchant charged the same price more often outside it than in it): it rejected genuine pairs of same-price subscriptions, and passed app-store purchases. The coincidence test replaced it.
