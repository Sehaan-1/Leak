# Slice 8: the public demo. Each visitor gets a throwaway household of
# synthetic data; demo_expires_at marks it for Demo::CleanupJob. NULL for
# real households.
class AddDemoExpiryToHouseholds < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :demo_expires_at, :datetime
    add_index :households, :demo_expires_at, where: "demo_expires_at IS NOT NULL"
  end
end
