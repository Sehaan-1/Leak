import "@testing-library/jest-dom/vitest";
import { File as NodeFile } from "node:buffer";
import { cleanup } from "@testing-library/react";
import { afterAll, afterEach, beforeAll } from "vitest";
import { loadTemporal } from "../lib/dates";
import { server } from "./server";

await loadTemporal();

// Rails puts this in the HTML shell.
const csrf = document.createElement("meta");
csrf.name = "csrf-token";
csrf.content = "test-csrf-token";
document.head.append(csrf);

// jsdom parses :user-invalid (and CSS.supports says yes) but never matches it,
// because it doesn't track user interaction. Report the truth so
// lib/fieldErrors.ts takes its interaction-tracking fallback, which is the
// path these tests can exercise.
const supports = CSS.supports.bind(CSS);
CSS.supports = ((...args: [string] | [string, string]) =>
  args.length === 1 && args[0].includes(":user-invalid")
    ? false
    : supports(...(args as [string]))) as typeof CSS.supports;

// fetch, Request and Response here are Node's (undici), but jsdom replaces
// File and FormData with its own, which undici can't read: uploads arrive
// renamed "blob" and, on Node 24, empty. Use Node's versions so a multipart
// upload in a test is built and sent exactly as a browser would send it.
const NodeFormData = (await new Response(new URLSearchParams()).formData()).constructor as typeof FormData;
Object.assign(globalThis, { File: NodeFile, FormData: NodeFormData });

beforeAll(() => server.listen({ onUnhandledFrame: "error" }));
afterEach(() => {
  cleanup();
  server.resetHandlers();
});
afterAll(() => server.close());
