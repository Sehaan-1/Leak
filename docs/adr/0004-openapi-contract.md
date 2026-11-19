# 4. OpenAPI file as the API contract

**Status:** accepted

## Context

A Rails API and a TypeScript client drift apart when types are written by
hand on both sides.

## Decision

`openapi/openapi.yaml` is the source of truth. Rails request specs validate
requests and responses against it with `committee`, a contract spec fails if
any `/api` route is undocumented (or documented but missing), and the web
client will generate its types with `openapi-typescript`.

## Consequences

- Changing a response shape without updating the spec fails CI.
- Schemas use `additionalProperties: false`, so accidental extra fields
  (such as leaking a column) also fail.
