# 3. Same-origin cookie sessions, not JWT

**Status:** accepted

## Context

The app holds a family's bank history. Tokens in `localStorage` are readable
by any script that runs on the page.

## Decision

Use the Rails 8 authentication generator: an `httpOnly`, `SameSite=Lax`,
signed `session_id` cookie backed by a `sessions` table, so sessions can be
revoked server-side. The SPA is served by Rails from a layout that embeds the
CSRF token, and sends it as `X-CSRF-Token` on writes. In development Vite
proxies `/api`, so everything stays same-origin. API endpoints answer `401`
JSON instead of redirecting.

## Consequences

- No auth gem and no token storage in the browser.
- Signing out deletes the session row; a stolen cookie stops working.
- The API is not meant for third-party clients; that is fine for this product.
