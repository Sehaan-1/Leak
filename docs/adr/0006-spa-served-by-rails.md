# 6. The SPA is served by Rails, built by Vite

**Status:** accepted

## Context

The React app talks to the API with a same-origin session cookie and Rails'
CSRF token (ADR 3). The token has to reach the page somehow, and the app has
to be served from the same origin as the API in development and production.

## Decision

- Rails renders the HTML shell (`SpaController#show`) with `csrf_meta_tags`.
  The app reads the token from the page and sends it as `X-CSRF-Token` on
  every write. No token endpoint and nothing in `localStorage`.
- Vite builds `web/` into `public/spa` with a manifest. A small helper
  (`ViteHelper`, about 40 lines) turns the manifest into script and
  stylesheet tags, instead of adding the `vite_rails` gem.
- In development the browser uses Vite on :5173, which proxies every path
  that isn't Vite's own to Rails. The page, API and assets share one origin,
  so cookies and CSRF behave exactly as in production, and hot reload works.
- The Docker image builds the SPA in a throwaway Node stage, so Node never
  reaches the runtime image.
- API types are generated from `openapi/openapi.yaml` into
  `web/src/api/schema.d.ts` (committed). CI regenerates them and fails on
  any difference, and `openapi-fetch` type-checks every call against them.
- Statement dates are calendar dates, shown with `Temporal.PlainDate` so they
  never shift with the device's time zone. `temporal-polyfill` is loaded
  only where `Temporal` is missing (Safari, at the time of writing).
- Money is formatted from integer paise via a decimal string with
  `Intl.NumberFormat("en-IN")`, never by dividing a float.

## Consequences

- One deployable, one origin. No CORS, no token juggling.
- `/` always serves the shell; the app decides between sign-in and the
  dashboard by calling `GET /api/v1/me`. The Rails HTML sign-in form remains
  as a fallback and lands on the same page.
- TypeScript is pinned to 5.9 because `openapi-typescript` 7 declares a
  peer dependency on TypeScript 5. Revisit when it supports 6+.
