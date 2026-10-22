# frozen_string_literal: true

# ms_graph_mailer (github.com/VandaPharma/ms_graph_mailer):
# send ActionMailer mail through Microsoft Graph.
# Every option is documented in
# https://github.com/VandaPharma/ms_graph_mailer/blob/main/docs/configuration.md
MsGraphMailer.configure do |config|
  # ---------------------------------------------------------------------------
  # Mailbox (same setting as GitLab's microsoft_graph_mailer 0.1.0)
  # ---------------------------------------------------------------------------
  # The mailbox Graph sends from. Every message is sent as this mailbox.
  config.user_id = "notifications@example.com"

  # true  - same as GitLab's microsoft_graph_mailer 0.1.0: MIME send, a copy is kept in the
  #         mailbox's Sent Items.
  # false - JSON send with saveToSentItems: false, no copy is kept. Graph then
  #         takes one body (HTML preferred) and the request must stay under ~4 MB.
  config.save_to_sent_items = false

  # ---------------------------------------------------------------------------
  # Entra app credentials
  # ---------------------------------------------------------------------------
  # Option A: AWS Secrets Manager (recommended for several apps sharing one Entra
  # app). The secret is JSON: {"tenant_id": "...", "client_id": "...", "client_secret": "..."}.
  # AWS access uses the default credential chain (e.g. the EC2 instance role).
  # Requires `gem "aws-sdk-secretsmanager"` in the application's Gemfile.
  # The secret is re-read every aws_secret_ttl seconds, and immediately when
  # Entra rejects it, so rotating it needs no restart.
  config.credentials_provider = :aws_secrets_manager
  config.aws_secret_id        = ENV.fetch("ENTRA_MAILER_SECRET_ID", "shared/entra-mailer/#{Rails.env}")
  config.aws_region           = ENV.fetch("ENTRA_MAILER_SECRET_REGION", "us-east-1")
  config.aws_secret_ttl       = ENV.fetch("ENTRA_SECRET_TTL_SECONDS", 600).to_i

  # Option B: static credentials, exactly like GitLab's microsoft_graph_mailer 0.1.0.
  # config.credentials_provider = :static
  # config.tenant        = ENV["ENTRA_TENANT_ID"]
  # config.client_id     = ENV["ENTRA_CLIENT_ID"]
  # config.client_secret = ENV["ENTRA_CLIENT_SECRET"]

  # National clouds only (defaults are the global endpoints).
  # config.azure_ad_endpoint = "https://login.microsoftonline.us"
  # config.graph_endpoint    = "https://graph.microsoft.us"

  # ---------------------------------------------------------------------------
  # From header
  # ---------------------------------------------------------------------------
  # Display name for the default From. A callable is evaluated for every message.
  config.display_name = -> { "<%= Rails.application.class.module_parent_name.titleize %>" }

  # Sets ActionMailer's default From to "<display_name> <user_id>".
  # Remove any `default from:` in ApplicationMailer, which would override it.
  config.set_default_from = true

  # A message whose From is not user_id is sent as user_id, shown as
  # "<original name> via <display_name>", with Reply-To set to the original address.
  config.enforce_from = true

  # ---------------------------------------------------------------------------
  # Delivery method switch
  # ---------------------------------------------------------------------------
  # nil (unset)       - Microsoft Graph in graph_environments; other environments
  #                     keep their own setting (letter_opener, :test, ...).
  # "microsoft_graph" - always Microsoft Graph.
  # "smtp"            - smtp_settings below (rollback path). Takes effect on restart.
  config.delivery_method    = ENV["MAIL_DELIVERY_METHOD"]
  config.graph_environments = %w[staging production]

  # Used only when MAIL_DELIVERY_METHOD=smtp.
  # config.smtp_settings = {
  #   address: "smtp.example.com",
  #   port: 587,
  #   enable_starttls_auto: true
  # }

  # ---------------------------------------------------------------------------
  # Reliability
  # ---------------------------------------------------------------------------
  # config.open_timeout          = 5   # seconds to open a connection
  # config.read_timeout          = 20  # seconds to wait for a response
  # config.max_transient_retries = 2   # in-process retries (deliver_now and deliver_later)
  # config.max_retry_sleep       = 2   # max seconds between in-process retries
  # config.job_retry_attempts    = 5   # deliver_later job attempts for transient errors

  # ---------------------------------------------------------------------------
  # Observability
  # ---------------------------------------------------------------------------
  # config.logger         = Rails.logger
  # config.error_notifier = ->(error, context) { Honeybadger.notify(error, context: context) }
end
