import { HttpResponse, http } from "msw";
import { setupServer } from "msw/node";
import { me, transactions } from "./fixtures";

export const unauthorized = () =>
  HttpResponse.json({ error: { code: "unauthorized", message: "Sign in to continue." } }, { status: 401 });

// Default: signed in, two transactions on one page.
export const server = setupServer(
  http.get("/api/v1/me", () => HttpResponse.json(me)),
  http.get("/api/v1/bank_transactions", () =>
    HttpResponse.json({ bank_transactions: transactions, next_page: null }),
  ),
);
