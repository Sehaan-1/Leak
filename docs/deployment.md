# Deployment

Two instances from one image with [Kamal 2](https://kamal-deploy.org), usually on one VPS ([design notes](design/deploy-and-public-demo.md)):

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
| `LEAK_PRIVATE_LLM_PROVIDER`, `_API_KEY`, `_MODEL`, `_BASE_URL` | optional, [the LLM step](../README.md#llm-provider) on the private instance; leave empty to skip it |
| `SSH_PRIVATE_KEY` | workflow only: a key the server accepts |

Keep the generated secrets somewhere safe (a password manager). **Losing the Active Record Encryption keys makes the stored narrations unreadable.** [`.kamal/secrets.<destination>`](../.kamal) only names the variables, so nothing secret is in git.

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

CI builds the production image on every push and boots it as the demo against Postgres (the `image` job, [`script/smoke-test-image`](../script/smoke-test-image)).

---

## Deploy for Free

You can deploy Leak completely free without needing a paid VPS or server:

### Option A: 1-Click Free Cloud Deploy on Render

Leak includes a `render.yaml` blueprint that provisions a free Docker web service and a free PostgreSQL database on [Render](https://render.com).

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/Sehaan-1/Leak)

1. Click the button above (or create a new Blueprint on Render and connect your GitHub repository).
2. Render reads `render.yaml`, spins up the free Postgres database, creates the required encryption keys automatically, and builds the container.
3. Your Leak instance will be live on a free `*.onrender.com` domain with automated HTTPS.

### Option B: Free Local or Cloud VM with Docker Compose

To run the full production stack for free on any machine (or free-tier cloud VM like Oracle Cloud Always Free, Google Cloud Free Tier, or AWS Free Tier):

```sh
# Clone repository
git clone https://github.com/Sehaan-1/Leak.git
cd Leak

# Start Postgres 18 and Leak in demo mode
docker compose up -d
```

Open `http://localhost:8080` in your browser. The database is prepared and seeded automatically on first boot.
