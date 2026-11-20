# Review queue answers teach the resolver; dismissals are anchored on ledger rows

## Problem

There are four screens: Import, Findings, Series detail and the Review queue. Two of them let the user say something the app must remember:

- **Review:** merchant resolution abstains instead of guessing (see [rules resolver](rules-merchant-resolution.md) and [LLM resolver](llm-merchant-resolution.md)). A household's abstained rows are usually a handful of payees repeated every month, such as "GOOGLE PLAY" with a YouTube Premium UPI ID. Asking about each row would be asking the same question twelve times.
- **Findings:** "Mark as OK" on a finding the user already knows about. `Detection::Run` deletes and rebuilds every series and finding on each run (see [detection](recurring-charge-detection.md)), so a finding's id doesn't survive the next import or review answer.

## Approach

- **Review answers are household aliases.** `Merchants::ManualResolution` sets the answered row to `resolution = manual` and, when the answer is a merchant, adds a household `merchant_aliases` row for the UPI ID, or for the payee name if there is no UPI ID and the name has at least 3 characters. It then resolves the household's other review rows again, so one answer clears the group, and reruns detection. Answers that aren't businesses (a person, the bank, cash) apply to the rows the user answered, and teach nothing: "a person" by name is too weak to generalise.
- **The queue groups rows** by UPI ID, otherwise by payee, and shows the payee, UPI ID, why resolution abstained and the raw narration. The user picks from the catalogue, with the non-business answers listed first.
- **Dismissals point at a ledger row, not a finding.** `finding_dismissals (household_id, kind, bank_transaction_id)` is unique, and its composite foreign key cascades when the row goes. The anchor is the first charge at the new price for a `price_increase`, otherwise the series' first charge. A rebuilt finding is dismissed if any of its evidence rows matches a dismissal of its kind. Ledger rows are the one thing detection never rewrites.
- **Series links can go stale.** The series screen is keyed by the current series id. If detection has since rebuilt it, the API returns 404, and the screen says the charges have moved and links back to Findings.
- **One end-to-end test** runs in CI (`web/e2e/`): Rails in the test environment serves the built SPA on a database seeded with a synthetic demo household (`lib/synthetic/demo_statement.rb`, imported through the real importer). It signs in, opens the Netflix price rise's charges, answers the Google Play review group and checks that YouTube Premium becomes a subscription.

## Trade-offs

- One review answer for the demo household resolves 10 rows and turns them into a subscription finding.
- A dismissal survives reimports, new statements and review answers, and goes away with the data it refers to. If a price rises again, the new step is a different row, so the new finding shows.
- A wrong merchant answer becomes an alias that affects future imports. Undoing an answer is not built yet.
- Series ids in URLs are only good until the next detection run.

## Not chosen

- **Stable series ids** (merchant + cadence + first charge as a natural key, upserted by `Detection::Run`): a series' first charge changes when an older statement is imported, so the key isn't stable either, and upserting complicates a run that is a pure rebuild today.
- **Dismissing by merchant:** it would hide a later price rise or a second subscription at the same merchant, which is exactly what the user should see.
