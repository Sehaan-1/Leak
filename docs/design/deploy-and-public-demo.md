# Two Kamal instances from one image; the public demo can't take real statements

## Problem

Leak has two audiences. The household needs a private instance for its real SBI statements. Everyone else (reviewers, anyone curious) needs to try it without an account and without uploading anything. The data model and the code are the same for both. The risk is not: a public server that accepts uploads will, sooner or later, receive somebody's real statement.

The budget is one small VPS, and the build runs on GitHub Actions only (no local Ruby is assumed).

## Approach

- **Kamal 2, two destinations, one image.** `config/deploy.yml` holds what they share. `config/deploy.demo.yml` and `config/deploy.private.yml` set the service (`leak-demo`, `leak-private`), the domain and the environment. Each has its own Postgres 18 accessory (`<service>-db`, not published, on Kamal's Docker network) and its own secrets, so neither can read the other's data, and both can share one server behind one kamal-proxy with Let's Encrypt. `require_destination: true`, so a bare `kamal deploy` refuses to guess.
- **Nothing about the server is in git.** Hosts come from `LEAK_SERVER`, `LEAK_DEMO_HOST`, `LEAK_PRIVATE_HOST`. `.kamal/secrets.<destination>` maps `LEAK_<DESTINATION>_*` environment variables to the container's names; `bin/rails 'leak:secrets[<destination>]'` prints a fresh set. The `Deploy` workflow (manual) reads them from repository secrets and pushes to ghcr.io with the job's token.
- **The demo is `LEAK_DEMO=1`:**
  - "Try it with made-up data" (`POST /api/v1/demo_session`) creates a household of its own for each visitor, imports a year of the fabricated SBI statement through the real importer, runs detection and signs the visitor in. The user has a random password nobody sees.
  - The household has `demo_expires_at` = 24 hours later. `Demo::CleanupJob` deletes expired ones every hour (Solid Queue, in Puma).
  - **Uploads return 403** (`demo_uploads_disabled`), checked before the file is read, and the Import screen says why instead of showing the form.
  - The demo has no LLM key; its review queue is part of the tour.
  - Creating demo households is rate-limited per IP (5 per 10 minutes).
- **The private instance has no sign-up.** Accounts are made on the server: `leak:users:create[email,household]`, run through `bin/kamal rails -d private`.
- **The production image is tested in CI** (`image` job): built, booted as the demo against Postgres 18 with throwaway secrets, and walked through the HTML shell, a demo session, findings, the upload refusal and "Delete my data". A second run checks it refuses to boot without its secrets.

## Trade-offs

- A real statement can only reach the private instance.
- One deploy pipeline and one image for both; a fix ships to both by deploying twice.
- Each demo visitor writes about 160 transactions; at the rate limit and with 24-hour expiry the demo database stays small, but a determined visitor with many IPs can still fill it. Scaling the demo means a shorter lifetime or a global cap.
- When a demo household is deleted, its user and sessions go with it, so an old demo cookie just signs out.
- Kamal's Let's Encrypt support needs one server per destination and port 443 open.

## Not chosen

- **One shared, read-only demo account:** visitors would see each other's review answers and dismissals, and resetting it would need a schedule. A throwaway household per visitor costs one import.
- **One instance with a "demo household":** the real statements and the public would share a database, secrets and an upload endpoint.
- **A static demo (screenshots or a recorded video):** it can't show the review queue or "Delete my data" working, and drifts from the app.
- **A PaaS:** more per month for two apps and two databases than one VPS, and Kamal is the Rails 8 default.
