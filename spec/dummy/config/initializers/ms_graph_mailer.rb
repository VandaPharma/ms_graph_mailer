# frozen_string_literal: true

MsGraphMailer.configure do |config|
  config.user_id            = "notifications@example.com"
  config.save_to_sent_items = false

  config.credentials_provider = :static
  config.tenant        = "tenant-id"
  config.client_id     = "client-id"
  config.client_secret = "client-secret"

  config.display_name     = -> { "Dummy App" }
  config.set_default_from = true

  config.delivery_method    = nil
  config.graph_environments = %w[test]
  config.smtp_settings      = { address: "smtp.example.com", port: 587 }

  config.max_retry_sleep = 1
end
