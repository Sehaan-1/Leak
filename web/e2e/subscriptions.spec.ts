import { expect, test } from "@playwright/test";

// The demo household (lib/synthetic/demo_statement.rb): Netflix went from
// ₹499 to ₹649 in July, JioHotstar runs twice, and YouTube Premium billed
// through Google Play is waiting in the review queue.
test("from sign-in to a price rise's evidence, then teaching Leak a merchant", async ({ page }) => {
  await page.goto("/");
  await page.getByLabel("Email address").fill("demo@leak.test");
  await page.getByLabel("Password", { exact: true }).fill("demo-password-change-me");
  await page.getByRole("button", { name: "Sign in" }).click();

  // Findings
  await expect(page.getByRole("heading", { level: 1, name: "Your subscriptions" })).toBeVisible();
  await expect(page.getByText(/^You pay/)).toHaveText("You pay ₹1,216.00 a month for 4 subscriptions.");
  const attention = page.getByRole("region", { name: "Needs a look" });
  await expect(attention.getByRole("article")).toHaveCount(2);
  await expect(attention).toContainText("Price went up from ₹499.00 to ₹649.00 on 5 Jul 2026.");
  await expect(attention).toContainText("A second JioHotstar subscription");

  // Series detail: the evidence behind the price rise
  await attention.getByRole("link", { name: "Netflix" }).click();
  await expect(page).toHaveURL(/#\/series\/\d+$/);
  await expect(page.getByRole("heading", { level: 1, name: "Netflix" })).toBeFocused();
  const charges = page.getByRole("table", { name: "Every Netflix charge, oldest first" });
  await expect(charges.getByRole("row")).toHaveCount(13);
  const step = charges.locator("tr.price-step");
  await expect(step).toHaveCount(1);
  await expect(step).toContainText("5 Jul 2026");
  await expect(step).toContainText("₹649.00");
  await expect(step).toContainText("New price");
  // The chart draws one bar per charge.
  await expect(page.locator(".chart .recharts-bar-rectangle")).toHaveCount(12);

  // Review queue: name the merchant once
  const nav = page.getByRole("navigation", { name: "Primary" });
  await nav.getByRole("link", { name: "Review, 12 to do" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Who were these payments to?" })).toBeVisible();
  const card = page.getByRole("article", { name: "GOOGLE PLAY" });
  await expect(card).toContainText("youtube.premium@okaxis");
  await card.getByLabel("Who was this?").selectOption({ label: "YouTube Premium" });
  await card.getByRole("button", { name: "Save" }).click();
  // The confirmation takes focus, so a screen reader reads it out.
  const saved = page.locator(".result-ok");
  await expect(saved).toBeFocused();
  await expect(saved).toContainText(
    "Saved: 10 payments to YouTube Premium. Leak will recognise youtube.premium@okaxis from now on.",
  );
  await expect(card).toHaveCount(0);
  await expect(nav.getByRole("link", { name: "Review, 2 to do" })).toBeVisible();

  // Detection ran again: YouTube Premium is now a subscription.
  await nav.getByRole("link", { name: "Findings" }).click();
  await expect(page.getByText(/^You pay/)).toHaveText("You pay ₹1,365.00 a month for 5 subscriptions.");
  const table = page.getByRole("table", { name: "Active subscriptions, most expensive first" });
  await expect(table.getByRole("link", { name: "YouTube Premium" })).toBeVisible();
});
