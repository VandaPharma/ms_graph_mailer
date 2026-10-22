# frozen_string_literal: true

# ms_graph_mailer (github.com/VandaPharma/ms_graph_mailer):
# send ActionMailer mail through Microsoft Graph.
# Every option is documented in
# https://github.com/VandaPharma/ms_graph_mailer/blob/main/docs/configuration.md
#
# Calling MsGraphMailer.configure makes :ms_graph the ActionMailer delivery method.
# Call it only where mail should go through Graph; elsewhere keep your own delivery
# method (letter_opener, :test, SMTP, ...). For example:
#
#   if Rails.env.production? || ENV["MAIL_DELIVERY_METHOD"] == "microsoft_graph"
#     MsGraphMailer.configure do |config|
#       ...
#     end
#   end
MsGraphMailer.configure do |config|
  # ---------------------------------------------------------------------------
  # Mailbox (same setting as GitLab's microsoft_graph_mailer 0.1.0)
  # ---------------------------------------------------------------------------
  # The mailbox Graph sends from. Every message is sent as this mailbox, so set
  # your mailers' From to this address (e.g. `default from:` in ApplicationMailer).
  config.user_id = "notifications@example.com"

  # true  - same as GitLab's microsoft_graph_mailer 0.1.0: MIME send, a copy is kept in the
  #         mailbox's Sent Items.
  # false - JSON send with saveToSentItems: false, no copy is kept. Graph then
  #         takes one body (HTML preferred) and the request must stay under ~4 MB.
  config.save_to_sent_items = false

  # ---------------------------------------------------------------------------
  # Entra app credentials: configure ONE of the two sources below
  # ---------------------------------------------------------------------------
  # credentials_provider (default :auto) picks the source from what is set:
  #   tenant/client_id/client_secret -> :static
  #   aws_secret_id                  -> :aws_secrets_manager
  # Setting both raises at boot unless credentials_provider names one of them.
  # config.credentials_provider = :auto   # or :static / :aws_secrets_manager

  # Option A: in this initializer, exactly like GitLab's microsoft_graph_mailer 0.1.0.
  # Read the values from ENV or Rails credentials; never commit the secret.
  # config.tenant        = ENV["ENTRA_TENANT_ID"]
  # config.client_id     = ENV["ENTRA_CLIENT_ID"]
  # config.client_secret = ENV["ENTRA_CLIENT_SECRET"]

  # Option B: AWS Secrets Manager (recommended when several apps share one Entra
  # app). The secret is JSON: {"tenant_id": "...", "client_id": "...", "client_secret": "..."}.
  # AWS access uses the default credential chain (e.g. the EC2 instance role).
  # Requires `gem "aws-sdk-secretsmanager"` in the application's Gemfile.
  # The secret is re-read every aws_secret_ttl seconds, and immediately when
  # Entra rejects it, so rotating it needs no restart.
  config.aws_secret_id  = ENV.fetch("ENTRA_MAILER_SECRET_ID", "shared/entra-mailer/#{Rails.env}")
  config.aws_region     = ENV.fetch("ENTRA_MAILER_SECRET_REGION", "us-east-1")
  config.aws_secret_ttl = ENV.fetch("ENTRA_SECRET_TTL_SECONDS", 600).to_i

  # National clouds only (defaults are the global endpoints).
  # config.azure_ad_endpoint = "https://login.microsoftonline.us"
  # config.graph_endpoint    = "https://graph.microsoft.us"

  # ---------------------------------------------------------------------------
  # From header
  # ---------------------------------------------------------------------------
  # Graph can only send as user_id. With enforce_from, a message whose From is
  # another address is sent as user_id, named "<original name> via <display_name>",
  # with Reply-To set to the original address.
  config.enforce_from = true
  config.display_name = -> { "<%= Rails.application.class.module_parent_name.titleize %>" }

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
