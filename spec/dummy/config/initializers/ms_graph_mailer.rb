# frozen_string_literal: true

MsGraphMailer.configure do |config|
  config.user_id            = "notifications@example.com"
  config.save_to_sent_items = false

  # Credentials given here; credentials_provider stays :auto and detects them.
  config.tenant        = "tenant-id"
  config.client_id     = "client-id"
  config.client_secret = "client-secret"

  config.display_name = -> { "Dummy App" }

  config.max_retry_sleep = 1
end
