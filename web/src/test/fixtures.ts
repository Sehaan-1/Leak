import type {
  BankTransaction,
  Finding,
  FindingsList,
  Me,
  Merchant,
  ReviewItem,
  ReviewList,
  SeriesCharge,
  SeriesDetail,
  SeriesSummary,
  StatementImport,
} from "../api/client";

// Typed from the generated OpenAPI schema, so these fixtures break the
// typecheck if the contract changes under them.
export const me: Me = {
  user: { id: 1, email_address: "asha@example.com" },
  household: { id: 1, name: "Sharma household" },
};

const account = { id: 3, name: "SBI ••9475" };

export const netflix: Merchant = { id: 1, slug: "netflix", name: "Netflix", category: "streaming" };
export const jiohotstar: Merchant = { id: 2, slug: "jiohotstar", name: "JioHotstar", category: "streaming" };
export const youtube: Merchant = {
  id: 3,
  slug: "youtube_premium",
  name: "YouTube Premium",
  category: "streaming",
};
export const spotify: Merchant = { id: 4, slug: "spotify", name: "Spotify", category: "music" };
export const merchants: Merchant[] = [jiohotstar, netflix, spotify, youtube];

export function transaction(
  overrides: Partial<BankTransaction> & Pick<BankTransaction, "id">,
): BankTransaction {
  return {
    posted_on: "2026-11-15",
    value_on: "2026-11-15",
    narration: "WDL TFR UPI/DR/631954012938/FRESH HARVEST/PUNB/freshharvest@pnb/Weekly Order",
    ref: null,
    amount_paise: -1_825_00,
    balance_after_paise: 24_850_75,
    bank_account: account,
    counterparty: null,
    merchant: null,
    needs_review: true,
    ...overrides,
  };
}

export const transactions: BankTransaction[] = [
  transaction({ id: 7 }),
  transaction({
    id: 1,
    posted_on: "2026-11-01",
    value_on: "2026-11-01",
    narration: "DEP TFR UPI/CR/630519482710/ANANYA ROY/UTIB/ananya.roy@okaxis/Transfer",
    amount_paise: 15_000_00,
    balance_after_paise: 27_450_25,
    counterparty: "person",
    needs_review: false,
  }),
];

export const importedStatement: StatementImport = {
  id: 9,
  status: "imported",
  filename: "sample_statement.pdf",
  period_from: "2026-11-01",
  period_to: "2026-11-19",
  opening_balance_paise: 12_450_25,
  closing_balance_paise: 24_850_75,
  rows_count: 7,
  new_rows_count: 7,
  error: null,
  bank_account: account,
  created_at: "2026-11-19T10:00:00Z",
};

function series(overrides: Partial<SeriesSummary> & Pick<SeriesSummary, "id" | "merchant">): SeriesSummary {
  return {
    cadence: "monthly",
    status: "active",
    amount_paise: 649_00,
    monthly_cost_paise: 649_00,
    first_charged_on: "2025-12-05",
    last_charged_on: "2026-11-05",
    next_expected_on: "2026-12-05",
    charges_count: 12,
    ...overrides,
  };
}

export const netflixSeries = series({ id: 21, merchant: netflix });
const hotstarFirst = series({
  id: 22,
  merchant: jiohotstar,
  amount_paise: 299_00,
  monthly_cost_paise: 299_00,
  first_charged_on: "2025-12-08",
  last_charged_on: "2026-11-08",
  next_expected_on: "2026-12-08",
});
const hotstarSecond = series({
  id: 23,
  merchant: jiohotstar,
  amount_paise: 149_00,
  monthly_cost_paise: 149_00,
  first_charged_on: "2026-05-22",
  last_charged_on: "2026-10-22",
  next_expected_on: "2026-11-22",
  charges_count: 6,
});
const spotifySeries = series({
  id: 24,
  merchant: spotify,
  amount_paise: 119_00,
  monthly_cost_paise: 119_00,
  first_charged_on: "2025-12-12",
  last_charged_on: "2026-11-12",
  next_expected_on: "2026-12-12",
});

function subscription(id: number, s: SeriesSummary): Finding {
  return {
    id,
    kind: "subscription",
    dismissed: false,
    amount_paise: s.amount_paise,
    monthly_cost_paise: s.monthly_cost_paise,
    previous_amount_paise: null,
    step_charge: null,
    series: s,
    related_series: null,
  };
}

export const priceIncrease: Finding = {
  ...subscription(101, netflixSeries),
  kind: "price_increase",
  previous_amount_paise: 499_00,
  step_charge: { id: 507, posted_on: "2026-07-05", charged_paise: 649_00 },
};

export const duplicate: Finding = {
  ...subscription(102, hotstarSecond),
  kind: "duplicate",
  related_series: hotstarFirst,
};

export const findingsList: FindingsList = {
  findings: [
    priceIncrease,
    duplicate,
    subscription(103, netflixSeries),
    subscription(104, hotstarFirst),
    subscription(105, hotstarSecond),
    subscription(106, spotifySeries),
  ],
  monthly_total_paise: 1_216_00,
  subscriptions_count: 4,
};

const netflixCharges: SeriesCharge[] = Array.from({ length: 12 }, (_, k) => {
  // Monthly on the 5th from December 2025. (No Temporal here: fixtures load
  // before the polyfill does.)
  const year = 2025 + Math.floor((11 + k) / 12);
  const month = String(((11 + k) % 12) + 1).padStart(2, "0");
  return {
    id: 500 + k,
    posted_on: `${year}-${month}-05`,
    charged_paise: k < 7 ? 499_00 : 649_00,
    level: k < 7 ? 0 : 1,
    price_step: k === 7,
    narration: `WDL TFR UPI/DR/6${k}1954012938/NETFLIX/ICIC/netflix@icici/Mandate`,
  };
});

export const netflixDetail: SeriesDetail = {
  ...netflixSeries,
  flagged: true,
  findings: [priceIncrease, subscription(103, netflixSeries)],
  charges: netflixCharges,
};

function reviewItem(overrides: Partial<ReviewItem> & Pick<ReviewItem, "id">): ReviewItem {
  return {
    posted_on: "2026-11-03",
    narration: "WDL TFR UPI/DR/612345678901/GOOGLE PLAY/UTIB/youtube.premium@okaxis/YouTube Premium",
    amount_paise: -149_00,
    payee: "GOOGLE PLAY",
    upi_id: "youtube.premium@okaxis",
    reason: "payee and UPI ID point to different merchants",
    bank_account: account,
    ...overrides,
  };
}

export const reviewList: ReviewList = {
  review_items: [
    reviewItem({ id: 301 }),
    reviewItem({ id: 302, posted_on: "2026-10-03" }),
    reviewItem({ id: 303, posted_on: "2026-09-03" }),
    reviewItem({
      id: 304,
      posted_on: "2026-08-15",
      narration: "WDL TFR UPI/DR/698765432109/SAI KRUPA TRADERS/YESB/q482915736@ybl/Payment",
      amount_paise: -640_00,
      payee: "SAI KRUPA TRADERS",
      upi_id: "q482915736@ybl",
      reason: 'no catalogue match for UPI payee "SAI KRUPA TRADERS"',
    }),
  ],
  total_count: 4,
};
