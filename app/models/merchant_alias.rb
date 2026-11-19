# One way a merchant shows up on a statement: a UPI ID or a normalised name.
# Global when household is nil; otherwise learnt for (and only used by) one
# household.
class MerchantAlias < ApplicationRecord
  belongs_to :merchant
  belongs_to :household, optional: true

  enum :kind, { vpa: "vpa", name: "name" }, prefix: :kind, validate: true

  validates :pattern, presence: true
  validate :pattern_is_normalised

  scope :for_household, ->(household) { where(household_id: [ nil, household&.id ].uniq) }

  def self.normalise(kind, text)
    kind.to_s == "vpa" ? Merchants::Text.vpa(text) : Merchants::Text.key(text)
  end

  private
    def pattern_is_normalised
      return if pattern.blank? || kind.blank?
      errors.add(:pattern, "isn't normalised") unless pattern == self.class.normalise(kind, pattern)
    end
end
