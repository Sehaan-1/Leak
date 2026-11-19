# Slice 5: the LLM resolver, for rows the rules abstain on.
#
# - resolution "llm": the LLM decided and the validators accepted it.
# - resolution_evidence: why (rules or LLM); encrypted, as it quotes the
#   narration. resolution_model: which model, for LLM verdicts.
# - llm_checked_at: the LLM has answered for this row; don't ask again.
# - Merchants with transactions can no longer be deleted. Nullifying
#   merchant_id broke the check that a merchant counterparty has a merchant.
class AddLlmResolution < ActiveRecord::Migration[8.1]
  def up
    add_enum_value :resolution_method, "llm", before: "abstained"

    change_table :bank_transactions, bulk: true do |t|
      t.text :resolution_evidence
      t.string :resolution_model
      t.datetime :llm_checked_at
    end

    remove_foreign_key :bank_transactions, :merchants
    add_foreign_key :bank_transactions, :merchants, on_delete: :restrict
  end

  def down
    remove_foreign_key :bank_transactions, :merchants
    add_foreign_key :bank_transactions, :merchants, on_delete: :nullify
    remove_column :bank_transactions, :llm_checked_at
    remove_column :bank_transactions, :resolution_model
    remove_column :bank_transactions, :resolution_evidence
    # PostgreSQL can't drop an enum value; "llm" stays in resolution_method.
  end
end
