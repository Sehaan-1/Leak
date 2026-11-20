import { HttpResponse, http } from "msw";
import { setupServer } from "msw/node";
import {
  findingsList,
  householdData,
  importedStatement,
  me,
  merchants,
  netflixDetail,
  reviewList,
  transactions,
} from "./fixtures";

export const unauthorized = () =>
  HttpResponse.json({ error: { code: "unauthorized", message: "Sign in to continue." } }, { status: 401 });

export const notFound = () =>
  HttpResponse.json({ error: { code: "not_found", message: "Not found." } }, { status: 404 });

// Default: signed in to a household with a year of statements.
export const server = setupServer(
  http.get("/api/v1/me", () => HttpResponse.json(me)),
  http.get("/api/v1/bank_transactions", () =>
    HttpResponse.json({ bank_transactions: transactions, next_page: null }),
  ),
  http.get("/api/v1/statement_imports", () => HttpResponse.json({ statement_imports: [importedStatement] })),
  http.get("/api/v1/findings", () => HttpResponse.json(findingsList)),
  http.get("/api/v1/recurring_series/:id", ({ params }) =>
    params.id === String(netflixDetail.id) ? HttpResponse.json(netflixDetail) : notFound(),
  ),
  http.get("/api/v1/review_items", () => HttpResponse.json(reviewList)),
  http.get("/api/v1/merchants", () => HttpResponse.json({ merchants })),
  http.get("/api/v1/household_data", () => HttpResponse.json(householdData)),
);
