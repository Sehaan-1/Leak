# 1. Money is integer paise

**Status:** accepted

## Context

Bank statements are exact. A recurring-charge finding is only credible if its
totals match the statement to the paisa, and the importer will reject
statements that don't reconcile. Floats can't represent 0.10 exactly, and
`BigDecimal` invites mixed-type arithmetic bugs.

## Decision

Every amount is an `Integer` number of paise in Ruby and `bigint` in
PostgreSQL. Columns are suffixed `_paise`, and so are API fields. Strings
become paise only through `Paise.parse`, which matches the full string
against a strict pattern (Indian `1,23,456.78` or Western `123,456.78`
grouping, at most two decimals) and never goes through `Float`.
`Paise.format` renders Indian grouping (`₹1,23,456.78`); the web client uses
`Intl.NumberFormat("en-IN")`.

## Consequences

- Statement totals reconcile with plain integer addition.
- `bigint` paise covers ±₹92 quadrillion; JSON numbers are exact up to
  ₹90 trillion, far beyond a household.
- A single currency (INR) is assumed. USD-billed subscriptions appear on
  statements already converted to rupees, which is what we record.
