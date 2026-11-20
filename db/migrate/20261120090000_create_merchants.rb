# Merchant resolution: a global catalogue of merchants with aliases (UPI IDs
# and normalised names), optional per-household aliases learnt from the
# review queue, and the resolver's verdict on each bank transaction.
#
# pg_trgm powers the fuzzy name match (similarity() over a GIN index).
class CreateMerchants < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"

    create_enum :merchant_category, %w[
      streaming music software cloud_storage news fitness education food_delivery groceries shopping
      transport travel fuel telecom internet dth utilities insurance investment loan credit_card rent
      healthcare wallet other
    ]
    create_enum :merchant_alias_kind, %w[ vpa name ]
    create_enum :counterparty_kind, %w[ merchant person bank cash ]
    create_enum :resolution_method, %w[ vpa_alias name_alias trigram rule abstained ]

    create_table :merchants do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.enum :category, enum_type: :merchant_category, null: false
      t.timestamps
    end
    add_index :merchants, :slug, unique: true

    create_table :merchant_aliases do |t|
      t.references :merchant, null: false, foreign_key: { on_delete: :cascade }
      # NULL: catalogue alias for everyone. Set: learnt for one household.
      t.references :household, foreign_key: { on_delete: :cascade }
      t.enum :kind, enum_type: :merchant_alias_kind, null: false
      # vpa: lower-case UPI ID ("netflix@icici"); name: A-Z0-9 only ("NETFLIXCOM").
      t.string :pattern, null: false
      t.timestamps
    end
    add_index :merchant_aliases, %i[ kind pattern household_id ], unique: true, nulls_not_distinct: true,
      name: "index_merchant_aliases_unique_pattern"
    add_index :merchant_aliases, :pattern, using: :gin, opclass: :gin_trgm_ops,
      name: "index_merchant_aliases_name_trgm"
    add_check_constraint :merchant_aliases, <<~SQL.squish, name: "merchant_aliases_pattern_normalised"
      (kind = 'name' AND pattern ~ '^[A-Z0-9]+$') OR (kind = 'vpa' AND pattern ~ '^[a-z0-9._-]+@[a-z0-9]+$')
    SQL

    change_table :bank_transactions, bulk: true do |t|
      t.references :merchant, foreign_key: { on_delete: :nullify }
      t.enum :counterparty, enum_type: :counterparty_kind
      t.enum :resolution, enum_type: :resolution_method
      t.datetime :resolved_at
    end
    # A merchant is set exactly when the counterparty is a merchant, and an
    # abstained resolution has no counterparty (it goes to review).
    add_check_constraint :bank_transactions, <<~SQL.squish, name: "bank_transactions_merchant_matches_counterparty"
      (merchant_id IS NOT NULL) = (counterparty IS NOT DISTINCT FROM 'merchant')
    SQL
    add_check_constraint :bank_transactions, <<~SQL.squish, name: "bank_transactions_resolution_consistent"
      (resolution IS NULL AND counterparty IS NULL AND resolved_at IS NULL)
      OR (resolution = 'abstained' AND counterparty IS NULL AND resolved_at IS NOT NULL)
      OR (resolution <> 'abstained' AND counterparty IS NOT NULL AND resolved_at IS NOT NULL)
    SQL
  end
end
