import { screen, waitFor, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { describe, expect, it } from "vitest";
import type { HouseholdData } from "./api/client";
import { demoMe, householdData } from "./test/fixtures";
import { renderApp } from "./test/render";
import { server, unauthorized } from "./test/server";

/** What Rails adds to the HTML shell on the public demo (LEAK_DEMO=1). */
function onDemoInstance() {
  const meta = document.createElement("meta");
  meta.name = "leak-demo";
  meta.content = "1";
  document.head.append(meta);
}

/** The value next to a label in the "What Leak keeps" list. */
async function fact(label: string) {
  return (await screen.findByText(label, { selector: "dt" })).nextElementSibling;
}

const empty: HouseholdData = {
  counts: { statements: 0, transactions: 0, subscriptions: 0, learned_merchants: 0, dismissed_findings: 0 },
  demo_expires_at: null,
};

describe("your data", () => {
  it("shows what Leak keeps", async () => {
    const { user } = renderApp();
    const nav = await screen.findByRole("navigation", { name: "Primary" });
    await user.click(within(nav).getByRole("link", { name: "Your data" }));

    expect(await screen.findByRole("heading", { level: 1, name: "Your data" })).toBeInTheDocument();
    expect(within(nav).getByRole("link", { name: "Your data" })).toHaveAttribute("aria-current", "page");
    expect(await fact("Transactions")).toHaveTextContent("160");
    expect(await fact("Payees you named in Review")).toHaveTextContent("1");
    expect(document.title).toBe("Your data · Leak");
  });

  it("asks before deleting, keeps the data on Keep, and deletes on Delete everything", async () => {
    let deleted = false;
    let requests = 0;
    server.use(
      http.get("/api/v1/household_data", () => HttpResponse.json(deleted ? empty : householdData)),
      http.delete("/api/v1/household_data", ({ request }) => {
        requests += 1;
        expect(request.headers.get("X-CSRF-Token")).toBe("test-csrf-token");
        deleted = true;
        return HttpResponse.json({ deleted: householdData.counts });
      }),
    );
    const { user } = renderApp("#/data");

    const open = await screen.findByRole("button", { name: "Delete my data…" });
    await fact("Transactions");
    await user.click(open);

    const dialog = screen.getByRole("dialog", { name: "Delete all your data?" });
    expect(dialog).toHaveTextContent("1 statement and 160 transactions will be deleted");
    expect(within(dialog).getByRole("button", { name: "Keep my data" })).toHaveFocus();

    await user.click(within(dialog).getByRole("button", { name: "Keep my data" }));
    expect(dialog).not.toHaveAttribute("open");
    expect(requests).toBe(0);

    await user.click(open);
    await user.click(within(dialog).getByRole("button", { name: "Delete everything" }));

    const done = await screen.findByText(/^Deleted/);
    expect(done).toHaveTextContent(
      "Deleted 1 statement and 160 transactions. Leak now holds no data of yours.",
    );
    await waitFor(() => expect(done.closest("div")).toHaveFocus());
    expect(requests).toBe(1);
    await waitFor(async () => expect(await fact("Transactions")).toHaveTextContent(/^0$/));
  });

  it("says nothing was deleted when the request fails", async () => {
    server.use(
      http.delete("/api/v1/household_data", () =>
        HttpResponse.json(
          { error: { code: "invalid_csrf_token", message: "Missing or invalid CSRF token." } },
          { status: 422 },
        ),
      ),
    );
    const { user } = renderApp("#/data");
    await user.click(await screen.findByRole("button", { name: "Delete my data…" }));
    await user.click(screen.getByRole("button", { name: "Delete everything" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Nothing was deleted. Missing or invalid CSRF token.",
    );
  });
});

describe("public demo", () => {
  it("offers a demo on the sign-in screen and signs in to it", async () => {
    onDemoInstance();
    let signedIn = false;
    server.use(
      http.get("/api/v1/me", () => (signedIn ? HttpResponse.json(demoMe) : unauthorized())),
      http.post("/api/v1/demo_session", () => {
        signedIn = true;
        return HttpResponse.json(demoMe, { status: 201 });
      }),
    );
    const { user } = renderApp();

    expect(await screen.findByRole("heading", { level: 1, name: "Try Leak" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Have an account? Sign in" })).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Try it with made-up data" }));

    expect(await screen.findByRole("heading", { level: 1, name: "Your subscriptions" })).toBeInTheDocument();
    expect(screen.getByText(/You're trying Leak with made-up data/)).toHaveTextContent(
      /It's all deleted on .*2026/,
    );
  });

  it("explains why there's no upload", async () => {
    onDemoInstance();
    renderApp("#/import");

    expect(await screen.findByText(/uploading statements is turned off/)).toBeInTheDocument();
    expect(screen.queryByLabelText(/statement/i, { selector: "input" })).not.toBeInTheDocument();
  });

  it("isn't offered on a private instance", async () => {
    server.use(http.get("/api/v1/me", unauthorized));
    renderApp();

    expect(await screen.findByRole("heading", { level: 1, name: "Sign in to Leak" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Try it with made-up data" })).not.toBeInTheDocument();
  });
});
