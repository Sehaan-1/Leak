# A business that money goes to or comes from. The catalogue is global
# (config/merchants.yml, synced by Merchants::Catalogue).
class Merchant < ApplicationRecord
  has_many :aliases, class_name: "MerchantAlias", dependent: :delete_all
  has_many :bank_transactions, dependent: :nullify

  enum :category, %w[
    streaming music software cloud_storage news fitness education food_delivery groceries shopping
    transport travel fuel telecom internet dth utilities insurance investment loan credit_card rent
    healthcare wallet other
  ].index_with(&:itself), prefix: :category, validate: true

  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :name, presence: true
end
