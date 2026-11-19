require "rails_helper"

RSpec.describe "detection tables constraints" do
  before { Merchants::Catalogue.sync! }

  let(:household) { create_household }
  let(:other) { create_household(name: "Other") }
  let(:netflix) { Merchant.find_by!(slug: "netflix") }
  let!(:txn) do
    Statements::Importer.import_text(household: household, text: sample_text, filename: "s.pdf")
    household.bank_transactions.first
  end
  let!(:series) { create_series(household) }

  def create_series(owner)
    owner.recurring_series.create!(merchant: netflix, cadence: "monthly", status: "active", flagged: true, amount_paise: 649_00,
      monthly_cost_paise: 649_00, first_charged_on: "2026-01-05", last_charged_on: "2026-06-05", next_expected_on: "2026-07-05",
      charges_count: 6)
  end

  def rejected(pattern, &block)
    expect { ApplicationRecord.transaction(requires_new: true, &block) }.to raise_error(ActiveRecord::StatementInvalid, pattern)
  end

  it "keeps charges and findings inside the series' household" do
    foreign = create_series(other)
    rejected(/fk_series_charges_series_same_household/) do
      RecurringSeriesCharge.insert_all!([ { household_id: household.id, recurring_series_id: foreign.id, bank_transaction_id: txn.id } ])
    end
    rejected(/fk_series_charges_transaction_same_household/) do
      RecurringSeriesCharge.insert_all!([ { household_id: other.id, recurring_series_id: foreign.id, bank_transaction_id: txn.id } ])
    end
    rejected(/fk_findings_related_series_same_household/) do
      household.findings.create!(recurring_series: series, kind: "duplicate", amount_paise: 1, monthly_cost_paise: 1, related_series: foreign)
    end
  end

  it "puts a transaction in at most one series" do
    second = create_series(household)
    RecurringSeriesCharge.create!(household_id: household.id, recurring_series: series, bank_transaction: txn)
    rejected(/index_recurring_series_charges_on_bank_transaction_id/) do
      RecurringSeriesCharge.create!(household_id: household.id, recurring_series: second, bank_transaction: txn)
    end
  end

  it "requires the evidence each kind of finding needs" do
    rejected(/findings_kind_details/) do
      household.findings.create!(recurring_series: series, kind: "price_increase", amount_paise: 649_00, monthly_cost_paise: 649_00)
    end
    rejected(/findings_kind_details/) do
      household.findings.create!(recurring_series: series, kind: "price_increase", amount_paise: 499_00, monthly_cost_paise: 499_00,
        previous_amount_paise: 649_00, step_transaction: txn)
    end
    rejected(/findings_kind_details/) do
      household.findings.create!(recurring_series: series, kind: "duplicate", amount_paise: 1, monthly_cost_paise: 1, related_series: series)
    end
    expect do
      household.findings.create!(recurring_series: series, kind: "price_increase", amount_paise: 649_00, monthly_cost_paise: 649_00,
        previous_amount_paise: 499_00, step_transaction: txn)
    end.not_to raise_error
  end

  it "rejects impossible series" do
    rejected(/recurring_series_dates_ordered/) { series.update_columns(next_expected_on: "2026-06-01") }
    rejected(/recurring_series_repeats/) { series.update_columns(charges_count: 1) }
    rejected(/recurring_series_amounts_positive/) { series.update_columns(amount_paise: 0) }
  end

  it "goes away with its transactions" do
    RecurringSeriesCharge.create!(household_id: household.id, recurring_series: series, bank_transaction: txn)
    household.findings.create!(recurring_series: series, kind: "price_increase", amount_paise: 649_00, monthly_cost_paise: 649_00,
      previous_amount_paise: 499_00, step_transaction: txn)
    BankTransaction.where(id: txn.id).delete_all
    expect(household.findings.count).to eq(0)
    expect(RecurringSeriesCharge.count).to eq(0)
  end
end
