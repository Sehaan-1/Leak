class Account < ApplicationRecord
  KINDS = %w[ asset liability equity income expense suspense ].freeze

  belongs_to :household
  has_many :postings, dependent: :restrict_with_exception

  validates :name, presence: true, uniqueness: { scope: :household_id }
  validates :kind, inclusion: { in: KINDS }

  # Accounts with their balance (sum of postings, debit-positive) in one query.
  scope :with_balances, -> {
    left_joins(:postings)
      .group(:id)
      .select("accounts.*, COALESCE(SUM(postings.amount_paise), 0)::bigint AS balance_paise")
  }

  def balance_paise
    has_attribute?(:balance_paise) ? self[:balance_paise] : postings.sum(:amount_paise)
  end
end
