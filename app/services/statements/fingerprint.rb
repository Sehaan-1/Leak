require "openssl"

module Statements
  # Deterministic identity of a statement line, used to make imports
  # idempotent. Two statements that both contain the same transaction
  # produce the same fingerprint, even if the narration wraps differently.
  #
  # The running balance is part of the key, so two identical charges on the
  # same day (same amount, same narration) stay distinct.
  #
  # HMAC'd with a key derived from secret_key_base, so the stored value
  # reveals nothing about the narration. Rotating secret_key_base changes
  # every fingerprint: re-key before rotating (see docs/adr/0005).
  module Fingerprint
    VERSION = "v1"

    module_function

    def for(bank_account, row)
      hmac([
        VERSION, bank_account.id, row.posted_on.iso8601, row.value_on.iso8601,
        row.amount_paise, row.balance_paise, row.narration.gsub(/\s+/, "").upcase
      ].join("|"))
    end

    def account_number_digest(bank, ifsc, account_number)
      hmac([ VERSION, "account", bank, ifsc, account_number ].join("|"))
    end

    def hmac(message)
      OpenSSL::HMAC.hexdigest("SHA256", key, message)
    end

    def key
      Rails.application.key_generator.generate_key("leak/statements/fingerprint", 32)
    end
  end
end
