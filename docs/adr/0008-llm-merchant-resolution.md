# 8. LLM merchant resolution: any provider, grounded answers, replayed in CI

Date: 2026-11-20 · Status: accepted

## Context

The rules resolver (ADR 7) abstains on about a quarter of the business rows in the synthetic sets, and on some person rows. Those rows need an LLM, but:

- the household chooses the provider. That can be any OpenAI-compatible API with their own key, a coding agent already installed on the machine (Antigravity's `agy` or `opencode`), or a free tier (Gemini, NVIDIA NIM);
- a model that guesses is worse than one that abstains. A wrong merchant hides a leak, or invents one;
- PR CI must stay offline and deterministic, and a model change must still be caught;
- real narrations name people the household pays.

## Decision

**Pipeline.** Rules first. Only rows the rules abstained on go to the LLM, 20 per request. The LLM returns one label per row, chosen from the catalogue slugs plus `person` or `unknown`, with its confidence and the evidence it relied on. Then validators decide. Anything they reject, and every `unknown`, stays in the review queue, with the reason stored as evidence. The LLM never sees amounts or dates, and never touches rows the rules decided.

**Validators** (`Merchants::Llm::Validator`):

1. The label is a catalogue slug or `person`. The JSON schema already enforces this when the provider supports schemas.
2. Confidence ≥ 0.7.
3. The evidence is really in the narration, compared space-free as the rules do. A model can't cite text that isn't there.
4. A merchant answer must agree with the evidence:
   - the longest catalogue name or UPI ID inside the evidence belongs to that merchant;
   - or, if no name is inside the evidence, that merchant is the closest trigram match to it of all merchants, at similarity ≥ 0.3. Rules alone need 0.5 and a 0.15 margin.

   So the LLM can read "HDFC STANDARD LIFE" as HDFC Life (0.37), but can't name a merchant from a payment gateway (RAZORPAY), an amount or a hunch.
5. A person answer needs:
   - a UPI or NEFT/IMPS row;
   - a payee that reads as a personal name (the same test the rules use);
   - no merchant-style UPI ID;
   - evidence that matches the payee.

**Providers** (`config/llm.yml`, `Merchants::Llm.client`), first match wins:

1. `LLM_PROVIDER` (or `credentials.llm.provider`) names a preset: gemini, nvidia, openai, openrouter, groq, ollama, agy, opencode or none.
2. `LLM_BASE_URL` on its own means any OpenAI-compatible endpoint.
3. Otherwise an installed agent: `agy`, then `opencode`.
4. Then `GEMINI_API_KEY`, then `NVIDIA_API_KEY`.
5. Otherwise nothing: rows stay in review.

The HTTP client uses only the standard library (`Net::HTTP`). It asks for a strict JSON schema, or a plain JSON object for providers without schema support, and retries 429 and 5xx responses, honouring `Retry-After`. Agents run headless in an empty temporary directory, with a timeout. The test environment never auto-detects a provider. A broken configuration logs a warning and disables the LLM; it never fails an import.

**Privacy.**
- Digit runs of five or more (references, account and phone numbers) are masked before a request leaves the app.
- Prompts and replies are never logged.
- Error messages carry the HTTP status and the provider's own error text, never the request.
- `resolution_evidence` is encrypted, because it quotes the narration.
- Free tiers may train on what they receive. For real statements, the README recommends a paid tier, a local model or the household's own agent.

**Storage.**
- `resolution = 'llm'`, with `resolution_model` and the evidence.
- `llm_checked_at` marks rows the LLM has answered, so they aren't sent again. A provider error stamps nothing, and the job retries.
- Imports enqueue `Merchants::LlmResolutionJob` after commit, but only when a provider is configured.
- `merchant_id` now uses `ON DELETE RESTRICT`. Nullifying it broke the check that a merchant counterparty has a merchant.

**Eval** (`LLM_EVAL=replay|live|record`):
- Rules + LLM runs on the same rows as rules only. On golden it must:
  - keep the 95% accuracy floor;
  - answer at least as many business rows;
  - beat rules only on net score, defined as correct − 3 × wrong over all rows, and not lose on business rows. A wrong merchant costs three right ones.
- PR CI replays recorded replies from `eval/merchant_resolution/replay/`, keyed by a hash of the request. Changing the prompt, the catalogue or the rows makes a recording stale, and CI fails until it is recorded again. If no recording exists, the LLM gate is skipped with a notice.
- `.github/workflows/llm-eval.yml` runs the live model:
  - on PRs touching the resolver, prompt, catalogue or eval;
  - nightly;
  - on demand. With `record=true` it commits new recordings.

## Consequences

- No LLM gate is enforced yet. GitHub Models, the planned no-secret CI provider, answered every request with a bare `OK` from this repo's runners, and no provider secret has been added. CI therefore runs the rules gate plus a skipped LLM step. Adding a `GEMINI_API_KEY` (or other) repository secret and running the LLM eval workflow with `record=true` turns the gate on.
- The headroom on golden-v1 is small by construction:
  - 45 of the 53 business rows the rules abstain on are labelled `unknown`. They are businesses outside the catalogue, so abstaining is the only correct answer.
  - 6 are gateway payments that never name the merchant.

  The LLM's measurable gains are a couple of NACH variants and person rows. Its value on real statements, with a long tail of local shops, is larger and unmeasured: the review queue will show it.
- `unknown` is not stored as an answer. The row stays in review with the LLM's reading (for example "not in the catalogue: CAFE MOCHA BANDRA"), which will seed new merchants or household aliases in slice 7.
- Agent CLIs are convenient locally but slow: each request starts the agent, and their output formats can change. They are a fallback, not the CI path.
