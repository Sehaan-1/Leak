import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import type { UserEvent } from "@testing-library/user-event";
import { HttpResponse, http } from "msw";
import { describe, expect, it } from "vitest";
import { importedStatement, me, transaction, transactions } from "./test/fixtures";
import { renderApp } from "./test/render";
import { server, unauthorized } from "./test/server";

const pdf = () => new File(["%PDF-1.4 sample"], "statement.pdf", { type: "application/pdf" });

// user-event sets input.files by overriding the property, which jsdom's own
// constraint validation can't see, so it would still call the field empty
// and block the submit. Dispatch submit directly once a file is chosen.
async function chooseAndSubmit(user: UserEvent) {
  const input = await screen.findByLabelText("SBI account statement (PDF)");
  await user.upload(input, pdf());
  fireEvent.submit(screen.getByRole("form", { name: "Import a statement" }));
}

describe("sign-in", () => {
  it("signs in with the CSRF token, then shows the household's transactions", async () => {
    let signedIn = false;
    let sent: { body: unknown; csrf: string | null } | undefined;
    server.use(
      http.get("/api/v1/me", () => (signedIn ? HttpResponse.json(me) : unauthorized())),
      http.post("/api/v1/session", async ({ request }) => {
        sent = { body: await request.json(), csrf: request.headers.get("X-CSRF-Token") };
        signedIn = true;
        return HttpResponse.json(me, { status: 201 });
      }),
    );
    const { user } = renderApp();

    const email = await screen.findByLabelText("Email address");
    const password = screen.getByLabelText("Password");
    // Autofill and password managers depend on these.
    expect(email).toHaveAttribute("autocomplete", "username");
    expect(email).toHaveAttribute("type", "email");
    expect(password).toHaveAttribute("autocomplete", "current-password");
    expect(email).toBeRequired();
    expect(password).toBeRequired();
    // No error state before interaction.
    expect(email).toHaveAttribute("aria-invalid", "false");

    await user.type(email, "asha@example.com");
    await user.type(password, "correct horse battery");
    await user.click(screen.getByRole("button", { name: "Sign in" }));

    const heading = await screen.findByRole("heading", { level: 1, name: "Sharma household" });
    await waitFor(() => expect(heading).toHaveFocus());
    expect(sent).toEqual({
      body: { session: { email_address: "asha@example.com", password: "correct horse battery" } },
      csrf: "test-csrf-token",
    });
    expect(await screen.findByRole("table")).toBeInTheDocument();
  });

  it("announces wrong credentials", async () => {
    server.use(
      http.get("/api/v1/me", unauthorized),
      http.post("/api/v1/session", () =>
        HttpResponse.json(
          { error: { code: "invalid_credentials", message: "Wrong email address or password." } },
          { status: 401 },
        ),
      ),
    );
    const { user } = renderApp();

    await user.type(await screen.findByLabelText("Email address"), "asha@example.com");
    await user.type(screen.getByLabelText("Password"), "nope");
    await user.click(screen.getByRole("button", { name: "Sign in" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("Wrong email address or password.");
    expect(screen.queryByRole("table")).not.toBeInTheDocument();
  });

  it("lets the user check the password they typed", async () => {
    server.use(http.get("/api/v1/me", unauthorized));
    const { user } = renderApp();

    const password = await screen.findByLabelText("Password");
    const toggle = screen.getByRole("button", { name: "Show password" });
    expect(toggle).toHaveAttribute("aria-pressed", "false");
    await user.click(toggle);
    expect(toggle).toHaveAttribute("aria-pressed", "true");
    expect(password).toHaveAttribute("type", "text");
  });

  it("flags an empty required field only after the user has been in it", async () => {
    server.use(http.get("/api/v1/me", unauthorized));
    const { user } = renderApp();

    const email = await screen.findByLabelText("Email address");
    expect(email).toHaveAttribute("aria-invalid", "false");
    expect(email).not.toHaveAccessibleDescription();

    await user.type(email, "a");
    await user.clear(email);
    await user.tab();

    expect(email).toHaveAttribute("aria-invalid", "true");
    expect(email).toHaveAccessibleDescription(/Enter your email address/);
  });
});

describe("transactions", () => {
  it("lists statement lines with dates, signed amounts and balances in rupees", async () => {
    renderApp();

    const table = await screen.findByRole("table", { name: "Bank transactions, newest first" });
    const [header, newest, oldest] = within(table).getAllByRole("row");
    expect(
      within(header as HTMLElement)
        .getAllByRole("columnheader")
        .map((th) => th.textContent),
    ).toEqual(["Date", "Details", "Amount", "Balance"]);
    expect(within(newest as HTMLElement).getByRole("rowheader")).toHaveTextContent("15 Nov 2026");
    expect(newest).toHaveTextContent("FRESH HARVEST");
    expect(newest).toHaveTextContent("Money out: -₹1,825.00");
    expect(newest).toHaveTextContent("₹24,850.75");
    expect(oldest).toHaveTextContent("Money in: +₹15,000.00");
    expect(screen.getByText(/Showing 2 transactions \(all of them\)/)).toBeInTheDocument();
    // The scroll container is keyboard-reachable and named.
    expect(screen.getByRole("region", { name: "Bank transactions, newest first" })).toHaveAttribute(
      "tabindex",
      "0",
    );
  });

  it("loads older pages on request", async () => {
    server.use(
      http.get("/api/v1/bank_transactions", ({ request }) => {
        const page = new URL(request.url).searchParams.get("page");
        return page === "2"
          ? HttpResponse.json({
              bank_transactions: [transaction({ id: 100, posted_on: "2026-10-30" })],
              next_page: null,
            })
          : HttpResponse.json({ bank_transactions: transactions, next_page: 2 });
      }),
    );
    const { user } = renderApp();

    await user.click(await screen.findByRole("button", { name: "Show older transactions" }));

    expect(await screen.findByText("30 Oct 2026")).toBeInTheDocument();
    expect(screen.getAllByRole("row")).toHaveLength(4);
    expect(screen.queryByRole("button", { name: "Show older transactions" })).not.toBeInTheDocument();
  });

  it("explains an empty ledger", async () => {
    server.use(
      http.get("/api/v1/bank_transactions", () =>
        HttpResponse.json({ bank_transactions: [], next_page: null }),
      ),
    );
    renderApp();
    expect(await screen.findByText(/No transactions yet/)).toBeInTheDocument();
  });
});

describe("statement upload", () => {
  it("uploads the PDF as multipart with the CSRF token and refreshes the list", async () => {
    let upload: { file: FormDataEntryValue | null; csrf: string | null } | undefined;
    let listed = 0;
    server.use(
      http.get("/api/v1/bank_transactions", () => {
        listed += 1;
        return HttpResponse.json({ bank_transactions: transactions, next_page: null });
      }),
      http.post("/api/v1/statement_imports", async ({ request }) => {
        const form = await request.formData();
        upload = { file: form.get("file"), csrf: request.headers.get("X-CSRF-Token") };
        return HttpResponse.json(importedStatement, { status: 201 });
      }),
    );
    const { user } = renderApp();

    await chooseAndSubmit(user);

    expect(await screen.findByText(/Statement imported/)).toHaveTextContent(
      "Statement imported for 1 Nov 2026 to 19 Nov 2026: 7 new transactions. Closing balance ₹24,850.75.",
    );
    expect(upload?.csrf).toBe("test-csrf-token");
    expect(upload?.file).toMatchObject({ name: "statement.pdf", type: "application/pdf", size: 15 });
    await waitFor(() => expect(listed).toBe(2));
  });

  it("says so when the statement was already imported", async () => {
    server.use(
      http.post("/api/v1/statement_imports", () => HttpResponse.json(importedStatement, { status: 200 })),
    );
    const { user } = renderApp();

    await chooseAndSubmit(user);

    expect(await screen.findByText(/already imported this statement/)).toBeInTheDocument();
  });

  it("shows why a statement was rejected", async () => {
    server.use(
      http.post("/api/v1/statement_imports", () =>
        HttpResponse.json(
          {
            ...importedStatement,
            status: "rejected",
            rows_count: 0,
            new_rows_count: 0,
            error: { message: "Balances don't add up on 04/11/2026.", line: 52 },
          },
          { status: 422 },
        ),
      ),
    );
    const { user } = renderApp();

    await chooseAndSubmit(user);

    expect(await screen.findByText(/Couldn't import this statement/)).toHaveTextContent(
      "Couldn't import this statement. Balances don't add up on 04/11/2026. Nothing was added.",
    );
  });

  it("doesn't send anything without a file", async () => {
    let posted = false;
    server.use(
      http.post("/api/v1/statement_imports", () => {
        posted = true;
        return HttpResponse.json(importedStatement, { status: 201 });
      }),
    );
    const { user } = renderApp();

    const input = await screen.findByLabelText("SBI account statement (PDF)");
    await user.click(screen.getByRole("button", { name: "Import statement" }));

    expect(input).toHaveAttribute("aria-invalid", "true");
    expect(input).toHaveAccessibleDescription(/Choose your statement PDF first/);
    expect(posted).toBe(false);
  });
});

describe("sign-out", () => {
  it("clears the household's data and returns to sign-in", async () => {
    server.use(http.delete("/api/v1/session", () => new HttpResponse(null, { status: 204 })));
    const { user, client } = renderApp();

    await user.click(await screen.findByRole("button", { name: "Sign out" }));

    const heading = await screen.findByRole("heading", { level: 1, name: "Sign in to Leak" });
    await waitFor(() => expect(heading).toHaveFocus());
    expect(client.getQueryData(["bank_transactions"])).toBeUndefined();
  });
});
