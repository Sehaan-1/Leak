import type { BankTransaction, Me, StatementImport } from "../api/client";

// Typed from the generated OpenAPI schema, so these fixtures break the
// typecheck if the contract changes under them.
export const me: Me = {
  user: { id: 1, email_address: "asha@example.com" },
  household: { id: 1, name: "Sharma household" },
};

const account = { id: 3, name: "SBI ••9475" };

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
