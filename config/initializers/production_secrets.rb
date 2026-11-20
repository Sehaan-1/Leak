# Fail at boot, not on the first statement import, if a production secret
# is missing. SECRET_KEY_BASE_DUMMY is set while the Docker image
# precompiles assets, when no secrets exist.
if Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
  required = %w[
    SECRET_KEY_BASE
    ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
    ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
    ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
  ]
  missing = required.select { |name| ENV[name].blank? }
  raise "Missing production secrets: #{missing.join(", ")}. See README › Deploying." if missing.any?
end
