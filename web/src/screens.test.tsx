import { screen, waitFor, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { describe, expect, it } from "vitest";
import type { Finding } from "./api/client";
import { priceIncrease, reviewList, youtube } from "./test/fixtures";
import { renderApp } from "./test/render";
import { server } from "./test/server";

describe("navigation", () => {
  it("marks the current screen, counts the review queue and focuses each new screen's heading", async () => {
    const { user } = renderApp();

    const nav = await screen.findByRole("navigation", { name: "Primary" });
    expect(within(nav).getByRole("link", { name: "Findings" })).toHaveAttribute("aria-current", "page");
    expect(await within(nav).findByRole("link", { name: "Review, 4 to do" })).toHaveAttribute(
      "href",
      "#/review",
    );

    await user.click(within(nav).getByRole("link", { name: "Review, 4 to do" }));

    const heading = await screen.findByRole("heading", { level: 1, name: "Who were these payments to?" });
    await waitFor(() => expect(heading).toHaveFocus());
    expect(within(nav).getByRole("link", { name: /Review/ })).toHaveAttribute("aria-current", "page");
    expect(document.title).toBe("Review · Leak");
  });
});

describe("findings", () => {
  it("sums the subscriptions and lists what needs a look, each linked to its charges", async () => {
    renderApp();

    expect(await screen.findByText(/You pay/)).toHaveTextContent(
      "You pay ₹1,216.00 a month for 4 subscriptions.",
    );
    const attention = screen.getByRole("region", { name: "Needs a look" });
    const [increase, duplicate] = within(attention).getAllByRole("article");

    expect(within(increase as HTMLElement).getByRole("link", { name: "Netflix" })).toHaveAttribute(
      "href",
      "#/series/21",
    );
    expect(increase).toHaveTextContent(
      "Price went up from ₹499.00 to ₹649.00 on 5 Jul 2026. That's ₹150.00 more every month.",
    );
    expect(within(duplicate as HTMLElement).getByRole("link", { name: "JioHotstar" })).toHaveAttribute(
      "href",
      "#/series/23",
    );
    expect(duplicate).toHaveTextContent(
      "A second JioHotstar subscription: ₹149.00 every month since May 2026, alongside the one at ₹299.00 since Dec 2025.",
    );
    expect(
      within(duplicate as HTMLElement).getByRole("link", { name: "See the first subscription's charges" }),
    ).toHaveAttribute("href", "#/series/22");

    const table = screen.getByRole("table", { name: "Active subscriptions, most expensive first" });
    const rows = within(table).getAllByRole("row").slice(1);
    expect(rows).toHaveLength(4);
    expect(within(rows[0] as HTMLElement).getByRole("link", { name: "Netflix" })).toHaveAttribute(
      "href",
      "#/series/21",
    );
    expect(rows[0]).toHaveTextContent("Monthly");
    expect(rows[0]).toHaveTextContent("5 Dec 2026");

    expect(screen.getByRole("link", { name: "Review them" })).toHaveAttribute("href", "#/review");
  });

  it("marks a finding as OK and can show it again", async () => {
    let sent: { method: string; csrf: string | null } | undefined;
    const reply =
      (dismissed: boolean) =>
      async ({ request }: { request: Request }) => {
        sent = { method: request.method, csrf: request.headers.get("X-CSRF-Token") };
        return HttpResponse.json<Finding>({ ...priceIncrease, dismissed }, { status: dismissed ? 201 : 200 });
      };
    server.use(
      http.post("/api/v1/findings/101/dismissal", reply(true)),
      http.delete("/api/v1/findings/101/dismissal", reply(false)),
    );
    const { user } = renderApp();

    await user.click(await screen.findByRole("button", { name: "Mark as OK: Netflix price went up" }));

    const dismissed = await screen.findByRole("region", { name: "Marked as OK" });
    expect(within(dismissed).getByRole("article")).toHaveTextContent("Price went up");
    expect(sent).toEqual({ method: "POST", csrf: "test-csrf-token" });
    expect(screen.getByRole("status")).toHaveTextContent("Netflix price went up marked as OK.");
    expect(screen.getByRole("heading", { name: "Needs a look" })).toHaveFocus();
    expect(within(screen.getByRole("region", { name: "Needs a look" })).getAllByRole("article")).toHaveLength(
      1,
    );

    await user.click(within(dismissed).getByRole("button", { name: "Show again: Netflix price went up" }));

    await waitFor(() =>
      expect(screen.queryByRole("region", { name: "Marked as OK" })).not.toBeInTheDocument(),
    );
    expect(sent?.method).toBe("DELETE");
  });

  it("points to import when there is nothing yet", async () => {
    server.use(
      http.get("/api/v1/findings", () =>
        HttpResponse.json({ findings: [], monthly_total_paise: 0, subscriptions_count: 0 }),
      ),
    );
    renderApp();
    expect(await screen.findByText(/No subscriptions found yet/)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Import a statement" })).toHaveAttribute("href", "#/import");
  });
});

describe("series detail", () => {
  it("opens from a finding and shows every charge, with the price step highlighted", async () => {
    const { user } = renderApp();

    const attention = await screen.findByRole("region", { name: "Needs a look" });
    await user.click(within(attention).getByRole("link", { name: "Netflix" }));

    const heading = await screen.findByRole("heading", { level: 1, name: "Netflix" });
    await waitFor(() => expect(heading).toHaveFocus());
    expect(screen.getByText("Price now").nextElementSibling).toHaveTextContent("₹649.00 every month");
    expect(screen.getByText(/^Price went up from/)).toHaveTextContent(
      "Price went up from ₹499.00 to ₹649.00 on 5 Jul 2026.",
    );

    const table = screen.getByRole("table", { name: "Every Netflix charge, oldest first" });
    const rows = within(table).getAllByRole("row").slice(1);
    expect(rows).toHaveLength(12);
    expect(rows[0]).toHaveTextContent("5 Dec 2025");
    expect(rows[0]).toHaveTextContent("₹499.00");
    const step = rows.filter((row) => row.classList.contains("price-step"));
    expect(step).toHaveLength(1);
    expect(step[0]).toHaveTextContent("5 Jul 2026");
    expect(step[0]).toHaveTextContent("₹649.00New price");

    expect(screen.getByText(/One bar per charge/)).toHaveTextContent(
      "The red bar on 5 Jul 2026 is the first charge at the new price.",
    );

    await user.click(screen.getByRole("button", { name: "Show the first charge at the new price" }));
    expect(step[0]).toHaveFocus();
    expect(window.location.hash).toBe("#/series/21");
  });

  it("explains a series that detection has since rebuilt", async () => {
    renderApp("#/series/99");
    expect(
      await screen.findByRole("heading", { level: 1, name: "These charges have moved" }),
    ).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Go back to your subscriptions" })).toHaveAttribute("href", "#/");
  });
});

describe("review queue", () => {
  it("asks once per UPI ID and teaches Leak the merchant", async () => {
    const posted: { id: string | undefined; body: unknown }[] = [];
    let answered = false;
    server.use(
      http.post("/api/v1/review_items/:id/resolution", async ({ params, request }) => {
        posted.push({ id: params.id as string, body: await request.json() });
        answered = true;
        return HttpResponse.json({
          review_item_id: 301,
          counterparty: "merchant",
          merchant: youtube,
          learned: { kind: "vpa", pattern: "youtube.premium@okaxis" },
          also_resolved_count: 2,
        });
      }),
      http.get("/api/v1/review_items", () =>
        HttpResponse.json(
          answered ? { review_items: reviewList.review_items.slice(3), total_count: 1 } : reviewList,
        ),
      ),
    );
    const { user } = renderApp("#/review");

    const card = await screen.findByRole("article", { name: "GOOGLE PLAY" });
    expect(card).toHaveTextContent("3, latest -₹149.00 on 3 Nov 2026 (-₹447.00 in all)");
    expect(card).toHaveTextContent("youtube.premium@okaxis");
    expect(card).toHaveTextContent("payee and UPI ID point to different merchants");
    expect(screen.getAllByRole("article")).toHaveLength(2);

    await user.selectOptions(within(card).getByLabelText("Who was this?"), "YouTube Premium");
    await user.click(within(card).getByRole("button", { name: "Save" }));

    const saved = await screen.findByText(/^Saved/);
    expect(saved).toHaveTextContent(
      "Saved: 3 payments to YouTube Premium. Leak will recognise youtube.premium@okaxis from now on.",
    );
    await waitFor(() => expect(saved.closest("div")).toHaveFocus());
    expect(posted).toEqual([{ id: "301", body: { counterparty: "merchant", merchant_id: youtube.id } }]);
    await waitFor(() =>
      expect(screen.queryByRole("article", { name: "GOOGLE PLAY" })).not.toBeInTheDocument(),
    );
    expect(screen.getByRole("article", { name: "SAI KRUPA TRADERS" })).toBeInTheDocument();
  });

  it("answers every row in a group that isn't a business", async () => {
    const ids: string[] = [];
    server.use(
      http.post("/api/v1/review_items/:id/resolution", ({ params }) => {
        ids.push(params.id as string);
        return HttpResponse.json({
          review_item_id: Number(params.id),
          counterparty: "person",
          merchant: null,
          learned: null,
          also_resolved_count: 0,
        });
      }),
    );
    const { user } = renderApp("#/review");

    const card = await screen.findByRole("article", { name: "GOOGLE PLAY" });
    await user.selectOptions(
      within(card).getByLabelText("Who was this?"),
      "A person (family, friend, someone I paid)",
    );
    await user.click(within(card).getByRole("button", { name: "Save" }));

    expect(await screen.findByText(/^Saved/)).toHaveTextContent("Saved: 3 payments marked as a person.");
    expect(ids).toEqual(["301", "302", "303"]);
  });

  it("says when there is nothing to review", async () => {
    server.use(
      http.get("/api/v1/review_items", () => HttpResponse.json({ review_items: [], total_count: 0 })),
    );
    renderApp("#/review");
    expect(await screen.findByText(/Nothing to review/)).toBeInTheDocument();
  });
});
