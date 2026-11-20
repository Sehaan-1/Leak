# Statement import: exact parsing, reconciliation, fingerprints

## Problem

The first real user banks with SBI and can download statements only as PDF
(text layer, no password). Every finding the app shows must trace back to
statement lines, and the same line must never be counted twice: statements
get re-downloaded and their periods overlap.

## Approach

- **Extraction:** poppler's `pdftotext -layout`, which keeps column
  positions. No OCR; a PDF without a text layer is rejected with a clear
  message. An optional PDF password goes straight to pdftotext and is never
  stored.
- **Parsing (per bank, no LLM):** `Statements::Parsers::Sbi` locates the
  columns from each page's table header (offsets differ between pages), starts
  a row on a line with two dates, joins wrapped narrations, and assigns
  amounts to Debit / Credit / Balance by their right edge. Any dated line it
  can't read rejects the statement.
- **Reconciliation:** each balance must equal the previous one plus credit
  minus debit; dates must be ordered and inside the period; the last balance
  must equal the header's closing balance when it's as of the period end.
  The opening balance is derived from the first row. A rejected statement
  writes nothing and records the reason and the text line.
- **Idempotency:** a statement line's fingerprint is
  HMAC(bank account, dates, amount, running balance, narration without
  whitespace), unique per household. The running balance keeps identical
  same-day charges apart; ignoring whitespace survives different line wraps.
  Re-uploading the same file (same SHA-256) returns the earlier import.
- **Opening balance:** the derived opening of the statement whose period
  starts earliest, kept as one system-maintained journal entry that is
  replaced when an earlier statement arrives. This is the single exception
  to "corrections are reversing entries" (see [ledger](double-entry-ledger.md)). It is derived data rather
  than an observed transaction, and replacing it makes the ledger identical
  whatever order statements are imported in.
- **Ledger:** each line posts bank account ↔ suspense. Merchant resolution
  then says who the other side was.
- **Privacy:** the PDF is never stored, only its SHA-256. Narrations and
  references are encrypted with Active Record Encryption. The account number
  is stored as its last four digits plus an HMAC for matching.
  `leak:redact` produces a shape-only copy of a statement for bug reports.

## Trade-offs

- Property tests cover import-twice, overlapping statements in any order,
  balanced entries, and ledger = latest closing balance; a missing month
  shows up as a reconciliation difference instead of silently.
- Fingerprints are keyed from `secret_key_base`. Rotating it requires
  re-fingerprinting existing rows first, or re-imports would duplicate.
- Supporting another bank means adding a parser and a fabricated fixture;
  reconciliation, fingerprints and posting are shared.
