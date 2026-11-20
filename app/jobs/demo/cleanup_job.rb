module Demo
  # Deletes demo households a day after they were created (config/recurring.yml).
  class CleanupJob < ApplicationJob
    queue_as :default

    def perform(now: Time.current)
      Household.expired_demo(now).find_each(&:destroy!)
    end
  end
end
