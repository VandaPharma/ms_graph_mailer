# ms_graph_mailer

Send ActionMailer email through the [Microsoft Graph `sendMail` API](https://learn.microsoft.com/graph/api/user-sendmail)
using the OAuth 2.0 client credentials flow, instead of SMTP.

Based on GitLab's [`microsoft_graph_mailer`](https://gitlab.com/gitlab-org/gitlab/-/tree/master/vendor/gems/microsoft_graph_mailer)
0.1.0 (MIT), with the same settings (`user_id`, `tenant`, `client_id`, `client_secret`,
`azure_ad_endpoint`, `graph_endpoint`) and the same MIME send by default. On top of that it adds:

- **`save_to_sent_items` setting**: keep or skip the copy in the sending mailbox's Sent Items.
- **Credentials from AWS Secrets Manager**: one Entra app shared by many Rails apps, with secret
  rotation that needs **no restart**. Read through the IAM role, or with AWS access keys from the
  initializer where there is no role. Credentials in the initializer work too.
- **Reliability**: cached access tokens, HTTP timeouts, short in-process retries for throttling
  and outages, and ActiveJob retries for `deliver_later`.
- **From enforcement**: a From on another address is sent as the mailbox
  (`"<Person> via <App Name>"`, Reply-To kept) instead of being rejected with `ErrorSendAsDenied`.
- **Rails integration**: Railtie, install generator, and `check` / `smoke` rake tasks.
- **PHI/PII-safe logging**: no secrets, tokens, recipients or message content in logs or errors.

The gem only handles Microsoft Graph. Choosing between Graph and another delivery method
(SMTP, `letter_opener`, `:test`) and setting your mailers' default From stay in your application;
see [docs/rails-integration.md](docs/rails-integration.md).

Supports Ruby 3.1 – 3.4 and Rails 6.1 – 8.1 (CI: Ruby 3.1.2 + Rails 6.1.7, Ruby 3.4.8 + Rails 8.1).

Install from this repository:

```ruby
gem "ms_graph_mailer", github: "VandaPharma/ms_graph_mailer", branch: "main"
# or pin a release: tag: "vX.Y.Z"
```

> The module is `MsGraphMailer`, which the unrelated `ms-graph-mailer` gem also uses; don't install
> both in one application.

## Contents

- [Quick start](#quick-start)
- [How it works](#how-it-works)
- [Configuration](#configuration): [all options](#all-options), [example with every option](#example-with-every-option)
- [Sent Items: MIME vs JSON](#sent-items-mime-vs-json)
- [Sending on behalf of a person](#sending-on-behalf-of-a-person)
- [deliver_now and deliver_later](#deliver_now-and-deliver_later)
- [Graph only where you want it (SMTP fallback)](#graph-only-where-you-want-it-smtp-fallback)
- [Rake tasks](#rake-tasks)
- [Using it without Rails](#using-it-without-rails)
- [Errors](#errors)
- Guides: [Entra and Exchange setup](docs/setup-entra.md) ·
  [AWS Secrets Manager setup](docs/setup-aws.md) ·
  [Rails integration and multiple apps](docs/rails-integration.md) ·
  [Runbooks](docs/runbooks.md) ·
  [Migrating from microsoft_graph_mailer](docs/migrating-from-microsoft_graph_mailer.md)

## Quick start

1. Register an Entra app that may send as your mailbox ([docs/setup-entra.md](docs/setup-entra.md)).
2. Store its credentials ([docs/setup-aws.md](docs/setup-aws.md)), or use static credentials.
3. Add the gem:

   ```ruby
   # Gemfile
   gem "ms_graph_mailer", github: "VandaPharma/ms_graph_mailer", branch: "main"
   gem "aws-sdk-secretsmanager", require: false # only when the credentials come from AWS Secrets Manager
   ```

4. Generate and edit the initializer:

   ```shell
   bin/rails generate ms_graph_mailer:install
   ```

   ```ruby
   # config/initializers/ms_graph_mailer.rb
   MsGraphMailer.configure do |config|
     config.user_id            = "notifications@example.com"
     config.save_to_sent_items = false

     # Entra app credentials: either in the initializer...
     # config.tenant        = ENV["ENTRA_TENANT_ID"]
     # config.client_id     = ENV["ENTRA_CLIENT_ID"]
     # config.client_secret = ENV["ENTRA_CLIENT_SECRET"]
     # ...or from AWS Secrets Manager:
     config.aws_secret_id = "shared/entra-mailer/#{Rails.env}"
     config.aws_region    = "us-east-1"

     config.display_name = -> { "My App" } # used when a From on another address is rewritten
   end
   ```

   Calling `MsGraphMailer.configure` makes `:ms_graph` the delivery method. Wrap it in a condition
   if some environments should keep another delivery method (see
   [below](#graph-only-where-you-want-it-smtp-fallback)).

5. Send From the mailbox, e.g. in `ApplicationMailer`:

   ```ruby
   default from: -> { email_address_with_name("notifications@example.com", "My App") }
   ```

6. Verify on a server: `bin/rails ms_graph_mailer:check`, then
   `bin/rails "ms_graph_mailer:smoke[you@example.com]"`.

Your mailers, views, and `deliver_now` / `deliver_later` calls stay as they are.

## How it works

```
deliver_now / deliver_later
        │   ActionMailer builds a new delivery object per message
        ▼
MsGraphMailer::Delivery
  1. From is not user_id?  → send as user_id, "<name> via <display_name>", Reply-To kept
  2. credentials           ← initializer settings, or AWS Secrets Manager (cached, TTL, reload on invalid_client)
  3. access token          ← cached in memory until ~5 minutes before expiry
  4. POST {graph}/v1.0/users/{user_id}/sendMail
       save_to_sent_items: true  → MIME body (as GitLab's 0.1.0)
       save_to_sent_items: false → JSON body with "saveToSentItems": false
  5. 429 / 5xx / connection failure → up to max_transient_retries short retries
     invalid_client → reload credentials, retry once;  401 → new token, retry once
```

## Configuration

All options are set in `config/initializers/ms_graph_mailer.rb` inside `MsGraphMailer.configure`.
The configuration is validated at boot: an invalid value raises `MsGraphMailer::ConfigurationError`
before any mail is sent. More detail on each group: [docs/configuration.md](docs/configuration.md).

### All options

**Mailbox and endpoints** (same as GitLab's `microsoft_graph_mailer` 0.1.0)

| Option | Default | Description |
|---|---|---|
| `user_id` | – (required) | Mailbox Graph sends from (email address/UPN or user object id). Every message is sent as this mailbox. |
| `azure_ad_endpoint` | `https://login.microsoftonline.com` | Entra token endpoint. National clouds, e.g. `https://login.microsoftonline.us` |
| `graph_endpoint` | `https://graph.microsoft.com` | Microsoft Graph endpoint. National clouds, e.g. `https://graph.microsoft.us` |

**Sent Items**

| Option | Default | Description |
|---|---|---|
| `save_to_sent_items` | `true` | `true`: MIME send (as GitLab's 0.1.0), a copy is kept in the mailbox's Sent Items. `false`: JSON send with `saveToSentItems: false`, no copy. See [Sent Items: MIME vs JSON](#sent-items-mime-vs-json). |

**Entra app credentials**: configure **one** of the two sources

| Option | Default | Description |
|---|---|---|
| `credentials_provider` | `:auto` | `:auto` uses whichever source below is set (both set = boot error, neither = boot error). `:static` or `:aws_secrets_manager` force one. Also accepts any object responding to `current` and `refresh!` (both return `{ tenant:, client_id:, client_secret: }`). |
| `tenant` | `nil` | *Initializer source:* directory (tenant) id or domain |
| `client_id` | `nil` | *Initializer source:* application (client) id |
| `client_secret` | `nil` | *Initializer source:* client secret value (read it from `ENV` or Rails credentials; never commit it) |
| `aws_secret_id` | `nil` | *AWS source:* Secrets Manager secret name or ARN holding `{"tenant_id", "client_id", "client_secret"}` |
| `aws_region` | `nil` (SDK default) | *AWS source:* region of the secret, e.g. `us-east-1` |
| `aws_secret_ttl` | `600` | *AWS source:* seconds before the cached secret is re-read. Also re-read immediately when Entra rejects it, so rotation needs no restart. |

**AWS access for reading the secret** (AWS source only)

| Option | Default | Description |
|---|---|---|
| `aws_access_key_id` | `nil` | Access key for Secrets Manager when no IAM role is available. Set together with `aws_secret_access_key`. |
| `aws_secret_access_key` | `nil` | Secret key paired with `aws_access_key_id` |
| `aws_session_token` | `nil` | Session token, only for temporary keys |

Leave the three unset to use the default AWS credential chain (EC2 instance role, ECS task role,
`AWS_*` environment variables, shared profile). Setting only one of the key pair raises at boot.
`bin/rails ms_graph_mailer:check` shows which is used; the secret key is never printed.

**From header**

| Option | Default | Description |
|---|---|---|
| `enforce_from` | `true` | Graph can only send as `user_id`. A message whose From is another address is sent as `user_id`, named `"<original name> via <display_name>"`, with Reply-To set to the original address. A missing From becomes `"<display_name> <user_id>"`. |
| `display_name` | `nil` | App name used by `enforce_from`. String or callable (evaluated per message), e.g. `-> { AppConfig["MAILER_EMAIL_NAME"] }` |

The gem does not set your mailers' default From; set it in the application (see [Quick start](#quick-start)).

**Reliability**

| Option | Default | Description |
|---|---|---|
| `open_timeout` | `5` | Seconds to open a connection to Entra or Graph |
| `read_timeout` | `20` | Seconds to wait for a response |
| `max_transient_retries` | `2` | In-process retries for 429, 5xx and connections that never opened (`deliver_now` and `deliver_later`) |
| `max_retry_sleep` | `2` | Maximum seconds between in-process retries (`Retry-After` is honoured up to this) |
| `job_retry_attempts` | `5` | `deliver_later` attempts for transient errors (`ActionMailer::MailDeliveryJob.retry_on`). `1` or less disables it. |

**Observability**

| Option | Default | Description |
|---|---|---|
| `logger` | `Rails.logger` | Boot summary, From rewrites, credential reloads. Never secrets, tokens, recipients or message content. |
| `error_notifier` | Honeybadger, if loaded | `->(error, context) { ... }`, called when a Secrets Manager refresh fails while a cached value is still in use |

### Example with every option

```ruby
# config/initializers/ms_graph_mailer.rb
MsGraphMailer.configure do |config|
  # Mailbox and endpoints
  config.user_id           = "notifications@example.com"
  config.azure_ad_endpoint = "https://login.microsoftonline.com"
  config.graph_endpoint    = "https://graph.microsoft.com"

  # Sent Items
  config.save_to_sent_items = false

  # Entra app credentials: ONE of the two sources
  config.credentials_provider = :auto # or :static / :aws_secrets_manager

  #   Initializer source
  # config.tenant        = ENV["ENTRA_TENANT_ID"]
  # config.client_id     = ENV["ENTRA_CLIENT_ID"]
  # config.client_secret = ENV["ENTRA_CLIENT_SECRET"]

  #   AWS Secrets Manager source
  config.aws_secret_id  = "shared/entra-mailer/#{Rails.env}"
  config.aws_region     = "us-east-1"
  config.aws_secret_ttl = 600

  #   AWS access for the secret: leave unset to use the IAM role
  # config.aws_access_key_id     = ENV["ENTRA_MAILER_AWS_ACCESS_KEY_ID"]
  # config.aws_secret_access_key = ENV["ENTRA_MAILER_AWS_SECRET_ACCESS_KEY"]
  # config.aws_session_token     = ENV["ENTRA_MAILER_AWS_SESSION_TOKEN"]

  # From header
  config.enforce_from = true
  config.display_name = -> { "My App" }

  # Reliability
  config.open_timeout          = 5
  config.read_timeout          = 20
  config.max_transient_retries = 2
  config.max_retry_sleep       = 2
  config.job_retry_attempts    = 5

  # Observability
  config.logger         = Rails.logger
  config.error_notifier = ->(error, context) { Honeybadger.notify(error, context: context) }
end
```

`bin/rails generate ms_graph_mailer:install` writes the same initializer with comments.

### Settings without `configure`

`MsGraphMailer::Delivery.new(settings)` and `config.action_mailer.ms_graph_settings = {...}` accept
the same options as a hash with the same names (e.g. `user_id:`, `aws_secret_id:`,
`aws_access_key_id:`, `save_to_sent_items:`), apart from `job_retry_attempts`, which only applies
through `configure`. See [Using it without Rails](#using-it-without-rails).

## Sent Items: MIME vs JSON

Graph only lets a sender skip the Sent Items copy when the message is sent as JSON.

| | `save_to_sent_items: true` | `save_to_sent_items: false` |
|---|---|---|
| Request | MIME (identical to GitLab's 0.1.0) | JSON with `"saveToSentItems": false` |
| Copy in the mailbox's Sent Items | Yes | No |
| Body | All parts as built by ActionMailer | One body: the HTML part if there is one, otherwise text |
| Headers | All | From, To, Cc, Bcc, Reply-To, Subject |
| Attachments | All | File and inline attachments (`cid:` images keep working) |
| Size limit | ~4 MB per request | ~4 MB per request |

Requests over the limit raise `DeliveryError` before anything is sent; validate attachment sizes in
your app. With `false`, nothing is stored in the mailbox, but tenant-wide journaling or
retention rules may still keep copies; check with your Microsoft 365 administrator.

## Sending on behalf of a person

Graph sends as the `user_id` mailbox only. For mail a person writes in your app (for example a
message to a customer), send from the shared mailbox and identify the person with Cc and Reply-To:

```ruby
mail(
  to: email.recipient,
  from: email_address_with_name("notifications@example.com", "#{user.full_name} via My App"),
  cc: user.email,
  reply_to: user.email,
  subject: email.subject
)
```

This works the same over SMTP. If a mailer sets a From on any other address, `enforce_from`
(default `true`) rewrites it to `"<name> via <display_name>" <user_id>` with Reply-To set to the
original address, so Exchange does not reject the message.

> Exchange Online may show the **mailbox's display name** instead of the name in the From header.
> Test this once with the smoke task (see [docs/runbooks.md](docs/runbooks.md#first-live-test)).

## deliver_now and deliver_later

Both work unchanged.

| | In-process (both) | `deliver_later` only |
|---|---|---|
| Throttling (429), Graph 5xx, connection never opened | Up to `max_transient_retries` (2) retries, each ≤ `max_retry_sleep` (2 s), honouring `Retry-After` | `ActionMailer::MailDeliveryJob.retry_on TransientError`, `job_retry_attempts` (5) with backoff |
| Read timeout | Not retried (the message may have been accepted; avoids duplicates) | Not retried |
| Rejected credentials (`invalid_client`) | Credentials reloaded, one retry | – |
| Permanent errors (403, 404, 400, too large) | Raised as `DeliveryError` | Raised |

Timeouts (`open_timeout` 5 s, `read_timeout` 20 s) keep a slow Graph call from holding a web
request for long.

## Graph only where you want it (SMTP fallback)

The gem does not choose delivery methods. Configure it only where mail should go through Graph,
and keep the application's own setting elsewhere. For example, Graph in staging and production
with an SMTP fallback through an environment variable:

```ruby
# config/initializers/ms_graph_mailer.rb
mail_delivery_method = ENV["MAIL_DELIVERY_METHOD"].presence ||
                       ("microsoft_graph" if Rails.env.staging? || Rails.env.production?)

case mail_delivery_method
when "smtp"
  ActionMailer::Base.delivery_method = :smtp
  ActionMailer::Base.smtp_settings = { address: "smtp.example.com", port: 587 }
when "microsoft_graph"
  MsGraphMailer.configure do |config|
    # ...
  end
when nil
  # development / test keep letter_opener, :test, ...
else
  raise ArgumentError, "MAIL_DELIVERY_METHOD must be microsoft_graph or smtp"
end
```

Job retries for transient Graph errors are only added when the gem is configured.

## Rake tasks

| Task | What it does |
|---|---|
| `bin/rails ms_graph_mailer:check` | Prints the active delivery method and, when the gem is configured, loads the credentials and requests a token. Sends nothing. Prints tenant and client IDs, never the secret. |
| `bin/rails "ms_graph_mailer:smoke[to@example.com]"` | Sends one test message through the active delivery method, with the application's default From |
| `bin/rails "ms_graph_mailer:smoke[to@example.com,Jane Doe via My App]"` | Same, with a custom From name, to check which name recipients see |

## Using it without Rails

```ruby
require "ms_graph_mailer"

delivery = MsGraphMailer::Delivery.new(
  user_id: "notifications@example.com",
  tenant: "YOUR-TENANT-ID",
  client_id: "YOUR-CLIENT-ID",
  client_secret: "YOUR-CLIENT-SECRET",
  save_to_sent_items: false
  # azure_ad_endpoint: "https://login.microsoftonline.us",  # national clouds
  # graph_endpoint:    "https://graph.microsoft.us"
)

message = Mail.new do
  from    "notifications@example.com"
  to      "to@example.com"
  subject "Hello"
  html_part { content_type "text/html; charset=UTF-8"; body "<p>Hello</p>" }
end

delivery.deliver!(message)
```

## Errors

| Class | When |
|---|---|
| `MsGraphMailer::ConfigurationError` | Invalid configuration (raised at boot) or a malformed secret |
| `MsGraphMailer::DeliveryError` | Permanent failure; `#status` (HTTP) and `#code` (Graph/Entra error code) |
| `MsGraphMailer::TransientError` | Retryable failure (subclass of `DeliveryError`); `#retry_after` |

Error messages contain the host, HTTP status and error code only, never response bodies,
recipients or credentials. Common codes are explained in [docs/runbooks.md](docs/runbooks.md#troubleshooting).

## Development

```shell
bundle install
bundle exec rake spec                                   # Rails 8.1
BUNDLE_GEMFILE=gemfiles/rails_6_1.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_6_1.gemfile bundle exec rake spec   # Rails 6.1 (Ruby 3.1)
```

Unit specs (`spec/unit`) and Rails integration specs (`spec/integration`, using `spec/dummy`) run
in separate processes. No test talks to the network.

## License and credits

MIT, see [LICENSE.txt](LICENSE.txt). Based on GitLab's
[microsoft_graph_mailer](https://gitlab.com/gitlab-org/gitlab/-/tree/master/vendor/gems/microsoft_graph_mailer),
Copyright (c) 2022 GitLab B.V.

Security issues: see [SECURITY.md](SECURITY.md).
