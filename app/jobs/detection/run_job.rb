module Detection
  # Re-runs recurring-charge detection for a household after its ledger or
  # merchants change (an import, or the LLM resolving rows).
  class RunJob < ApplicationJob
    queue_as :default

    discard_on ActiveRecord::RecordNotFound

    def perform(household_id)
      result = Run.new(household: Household.find(household_id)).call
      Rails.logger.info("[detection] household #{household_id}: #{result.series.size} series, #{result.findings.size} findings")
    end
  end
end
