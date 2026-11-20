import createClient, { type Middleware } from "openapi-fetch";
import type { components, paths } from "./schema";

export type Me = components["schemas"]["Me"];
export type BankTransaction = components["schemas"]["BankTransaction"];
export type StatementImport = components["schemas"]["StatementImport"];
export type Merchant = components["schemas"]["Merchant"];
export type Counterparty = components["schemas"]["Counterparty"];
export type Finding = components["schemas"]["Finding"];
export type SeriesSummary = components["schemas"]["SeriesSummary"];
export type SeriesDetail = components["schemas"]["SeriesDetail"];
export type SeriesCharge = components["schemas"]["SeriesCharge"];
export type ReviewItem = components["schemas"]["ReviewItem"];
export type FindingsList =
  paths["/api/v1/findings"]["get"]["responses"]["200"]["content"]["application/json"];
export type ReviewList =
  paths["/api/v1/review_items"]["get"]["responses"]["200"]["content"]["application/json"];
export type Resolution =
  paths["/api/v1/review_items/{review_item_id}/resolution"]["post"]["responses"]["200"]["content"]["application/json"];
type ErrorBody = components["schemas"]["Error"];

/** A non-2xx response, carrying the API's `{ error: { code, message } }` when present. */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code?: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

// Rails embeds the CSRF token in the HTML shell it serves; every write must
// echo it back. The session itself is an httpOnly same-origin cookie.
const csrf: Middleware = {
  onRequest({ request }) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content;
      if (token) request.headers.set("X-CSRF-Token", token);
    }
    request.headers.set("Accept", "application/json");
    return request;
  },
};

export const api = createClient<paths>({
  baseUrl: window.location.origin,
  credentials: "same-origin",
  // Look fetch up per request (not once at import) so test doubles and
  // polyfills installed later are used.
  fetch: (request) => globalThis.fetch(request),
});
api.use(csrf);

export function toApiError(error: unknown, response: Response): ApiError {
  const body = error as Partial<ErrorBody> | undefined;
  const message = body?.error?.message ?? `The server answered ${response.status}. Please try again.`;
  return new ApiError(response.status, message, body?.error?.code);
}

export async function getMe(): Promise<Me | null> {
  const { data, error, response } = await api.GET("/api/v1/me");
  if (response.status === 401) return null;
  if (!data) throw toApiError(error, response);
  return data;
}

export async function signIn(email_address: string, password: string): Promise<Me> {
  const { data, error, response } = await api.POST("/api/v1/session", {
    body: { session: { email_address, password } },
  });
  if (!data) throw toApiError(error, response);
  return data;
}

export async function signOut(): Promise<void> {
  const { error, response } = await api.DELETE("/api/v1/session");
  if (!response.ok && response.status !== 401) throw toApiError(error, response);
}

export type TransactionsPage = { bank_transactions: BankTransaction[]; next_page: number | null };

export async function listTransactions(page: number): Promise<TransactionsPage> {
  const { data, error, response } = await api.GET("/api/v1/bank_transactions", {
    params: { query: { page } },
  });
  if (!data) throw toApiError(error, response);
  return data;
}

export type UploadOutcome =
  | { kind: "imported"; statement: StatementImport }
  | { kind: "already_imported"; statement: StatementImport }
  | { kind: "rejected"; message: string; line: number | null };

/** Uploads a statement PDF. A rejected statement is an outcome to show, not an exception. */
export async function uploadStatement(file: File): Promise<UploadOutcome> {
  const form = new FormData();
  // Name the part explicitly: some FormData/File pairings otherwise send "blob",
  // and the server records the original filename.
  form.append("file", file, file.name);
  const { data, error, response } = await api.POST("/api/v1/statement_imports", {
    // The generated type models the binary part as a string; send the real FormData.
    body: { file: file.name },
    bodySerializer: () => form,
  });
  if (data) return { kind: response.status === 201 ? "imported" : "already_imported", statement: data };

  if (response.status === 422 && error && "status" in error && error.error) {
    return { kind: "rejected", message: error.error.message, line: error.error.line };
  }
  throw toApiError(error, response);
}

export async function listStatementImports(): Promise<StatementImport[]> {
  const { data, error, response } = await api.GET("/api/v1/statement_imports");
  if (!data) throw toApiError(error, response);
  return data.statement_imports;
}

export async function listFindings(): Promise<FindingsList> {
  const { data, error, response } = await api.GET("/api/v1/findings");
  if (!data) throw toApiError(error, response);
  return data;
}

/** Detection rebuilds series on every run, so an old id answers 404 (an ApiError with status 404). */
export async function getSeries(id: number): Promise<SeriesDetail> {
  const { data, error, response } = await api.GET("/api/v1/recurring_series/{id}", {
    params: { path: { id } },
  });
  if (!data) throw toApiError(error, response);
  return data;
}

export async function setFindingDismissed(id: number, dismissed: boolean): Promise<Finding> {
  const params = { params: { path: { finding_id: id } } };
  const { data, error, response } = dismissed
    ? await api.POST("/api/v1/findings/{finding_id}/dismissal", params)
    : await api.DELETE("/api/v1/findings/{finding_id}/dismissal", params);
  if (!data) throw toApiError(error, response);
  return data;
}

export async function listReviewItems(): Promise<ReviewList> {
  const { data, error, response } = await api.GET("/api/v1/review_items");
  if (!data) throw toApiError(error, response);
  return data;
}

export async function listMerchants(): Promise<Merchant[]> {
  const { data, error, response } = await api.GET("/api/v1/merchants");
  if (!data) throw toApiError(error, response);
  return data.merchants;
}

export type Answer =
  | { counterparty: "merchant"; merchant_id: number }
  | { counterparty: Exclude<Counterparty, "merchant"> };

export async function resolveReviewItem(id: number, answer: Answer): Promise<Resolution> {
  const { data, error, response } = await api.POST("/api/v1/review_items/{review_item_id}/resolution", {
    params: { path: { review_item_id: id } },
    body: answer,
  });
  if (!data) throw toApiError(error, response);
  return data;
}

export type DataCounts = components["schemas"]["DataCounts"];
export type HouseholdData =
  paths["/api/v1/household_data"]["get"]["responses"]["200"]["content"]["application/json"];

/** True on the public demo (LEAK_DEMO=1): Rails marks the HTML shell it serves. */
export function isDemoInstance(): boolean {
  return document.querySelector('meta[name="leak-demo"]') !== null;
}

/** Public demo only: a fresh household of made-up data, signed in. */
export async function startDemo(): Promise<Me> {
  const { data, error, response } = await api.POST("/api/v1/demo_session");
  if (!data) throw toApiError(error, response);
  return data;
}

export async function getHouseholdData(): Promise<HouseholdData> {
  const { data, error, response } = await api.GET("/api/v1/household_data");
  if (!data) throw toApiError(error, response);
  return data;
}

/** "Delete my data": everything imported, detected or learnt. The sign-in stays. */
export async function deleteHouseholdData(): Promise<DataCounts> {
  const { data, error, response } = await api.DELETE("/api/v1/household_data");
  if (!data) throw toApiError(error, response);
  return data.deleted;
}
