# Configuration reference

All options are set in `config/initializers/ms_graph_mailer.rb`:

```ruby
MsGraphMailer.configure do |config|
  config.option = value
end
```

`bin/rails generate ms_graph_mailer:install` writes a commented initializer with
every option. The configuration is validated when ActionMailer loads; an invalid combination
raises `MsGraphMailer::ConfigurationError` at boot, not at the first email.

Calling `MsGraphMailer.configure` makes `:ms_graph` the ActionMailer delivery method. The gem has
no SMTP or delivery-method switch: call `configure` only where mail should go through Graph (see
[rails-integration.md](rails-integration.md#graph-in-some-environments-smtp-or-others-elsewhere)).
Your mailers' default From is also set by your application, not by the gem.

## Mailbox and endpoints (same as GitLab's 0.1.0)

| Option | Default | Description |
|---|---|---|
| `user_id` | – (required for Graph) | Mailbox the message is sent from: an email address/UPN or a user object id. All mail is sent as this mailbox. `enforce_from` only applies when it is an email address. |
| `azure_ad_endpoint` | `https://login.microsoftonline.com` | Token endpoint host. National clouds: e.g. `https://login.microsoftonline.us` |
| `graph_endpoint` | `https://graph.microsoft.com` | Graph host. National clouds: e.g. `https://graph.microsoft.us` |

## Sent Items

| Option | Default | Description |
|---|---|---|
| `save_to_sent_items` | `true` | `true`: MIME send, exactly as GitLab's 0.1.0; Graph keeps a copy in the mailbox's Sent Items. `false`: JSON send with `saveToSentItems: false`; no copy. See [README](../README.md#sent-items-mime-vs-json) for the differences. |

## Credentials

The Entra app credentials come from **one** of two sources:

| Source | Set | Rotation |
|---|---|---|
| The initializer (`:static`) | `tenant`, `client_id`, `client_secret` (e.g. from `ENV` or Rails credentials) | Deploy the new value and restart |
| AWS Secrets Manager (`:aws_secrets_manager`) | `aws_secret_id` (and `aws_region`) | Update the secret; no restart |

```ruby
# Option A: in the initializer
config.tenant        = ENV["ENTRA_TENANT_ID"]
config.client_id     = ENV["ENTRA_CLIENT_ID"]
config.client_secret = ENV["ENTRA_CLIENT_SECRET"]

# Option B: AWS Secrets Manager
config.aws_secret_id = "shared/entra-mailer/#{Rails.env}"
config.aws_region    = "us-east-1"
```

With the default `credentials_provider = :auto`, the gem uses whichever source is set. If both
are set, boot fails with `ConfigurationError` unless `credentials_provider` names one; if neither
is set, boot fails with a message listing both options (only in environments that use Graph).

| Option | Default | Description |
|---|---|---|
| `credentials_provider` | `:auto` | `:auto` (detect from the settings), `:static`, `:aws_secrets_manager`, or any object responding to `current` and `refresh!` (both return `{ tenant:, client_id:, client_secret: }`) |
| `tenant` | `nil` | Initializer source: directory (tenant) id or domain |
| `client_id` | `nil` | Initializer source: application (client) id |
| `client_secret` | `nil` | Initializer source: client secret value |
| `aws_secret_id` | `nil` | AWS source: secret name or ARN |
| `aws_region` | `nil` (SDK default chain) | AWS: region of the secret, e.g. `us-east-1` |
| `aws_secret_ttl` | `600` | AWS: seconds before the cached secret is re-read |

### AWS Secrets Manager secret format

```json
{ "tenant_id": "00000000-0000-0000-0000-000000000000",
  "client_id": "00000000-0000-0000-0000-000000000000",
  "client_secret": "..." }
```

(`"tenant"` is accepted instead of `"tenant_id"`.)

- Requires `gem "aws-sdk-secretsmanager"` in the application's Gemfile.
- AWS credentials come from the SDK's default chain: EC2 instance role, ECS task role,
  `AWS_*` environment variables, or a shared profile. No AWS keys are configured in this gem.
- The secret is read on the first email, not at boot, so `assets:precompile` and `db:migrate` do
  not need AWS access.
- Each process caches the secret in memory (never in Redis, files or logs) for `aws_secret_ttl`
  seconds. When Entra rejects it (`invalid_client`), it is re-read immediately (at most once per
  30 seconds) and the message is retried once. **Rotating the secret needs no restart.**
- If AWS is unreachable after a value has been cached, the last good value stays in use and the
  error goes to `error_notifier`. If nothing is cached yet, the delivery raises `TransientError`.

## From header

Graph can only send as `user_id`, so your mailers should send From that address. The gem does not
set a default From; set it in your application (e.g. `default from:` in `ApplicationMailer`).

| Option | Default | Description |
|---|---|---|
| `enforce_from` | `true` | A message whose From is not `user_id` is sent as `user_id` with the name `"<original name or address> via <display_name>"` and Reply-To set to the original address (unless Reply-To is already set). Prevents Exchange `ErrorSendAsDenied`. A missing From becomes `"<display_name> <user_id>"`. Only applies when `user_id` is an email address. |
| `display_name` | `nil` | App name used by `enforce_from`. String or callable (evaluated for every message): `-> { AppConfig["MAILER_EMAIL_NAME"] }` |

## Reliability

| Option | Default | Description |
|---|---|---|
| `open_timeout` | `5` | Seconds to open a connection to Entra or Graph |
| `read_timeout` | `20` | Seconds to wait for a response |
| `max_transient_retries` | `2` | In-process retries for 429, 5xx and connections that never opened (`deliver_now` and `deliver_later`) |
| `max_retry_sleep` | `2` | Upper bound in seconds for each in-process wait (`Retry-After` is honoured up to this) |
| `job_retry_attempts` | `5` | `ActionMailer::MailDeliveryJob.retry_on TransientError, attempts:` for `deliver_later`. `1` or less disables it. Backoff: `:polynomially_longer` (Rails ≥ 7.1) or `:exponentially_longer` (Rails 6.1/7.0). Added only when the gem is configured. |

Read timeouts are never retried automatically: Graph may already have accepted the message.

## Observability

| Option | Default | Description |
|---|---|---|
| `logger` | `Rails.logger` | Logs the Graph configuration at boot, From rewrites, credential reloads. Never secrets, tokens, recipients or content. |
| `error_notifier` | Honeybadger, if loaded | `->(error, context) { ... }`, called when a Secrets Manager refresh fails while a cached value is still in use |

## Environment variables

The gem reads no environment variables itself. Your initializer may, for example the generated
template's `ENTRA_MAILER_SECRET_ID`, `ENTRA_MAILER_SECRET_REGION` and `ENTRA_SECRET_TTL_SECONDS`, or
`ENTRA_TENANT_ID` / `ENTRA_CLIENT_ID` / `ENTRA_CLIENT_SECRET` for credentials in the initializer.
