# ms_graph_mailer

Send ActionMailer email through the [Microsoft Graph `sendMail` API](https://learn.microsoft.com/graph/api/user-sendmail)
using the OAuth 2.0 client credentials flow, instead of SMTP.

Based on GitLab's [`microsoft_graph_mailer`](https://gitlab.com/gitlab-org/gitlab/-/tree/master/vendor/gems/microsoft_graph_mailer)
0.1.0 (MIT), with the same settings (`user_id`, `tenant`, `client_id`, `client_secret`,
`azure_ad_endpoint`, `graph_endpoint`) and the same MIME send by default. On top of that it adds:

- **`save_to_sent_items` setting**: keep or skip the copy in the sending mailbox's Sent Items.
- **Credentials from AWS Secrets Manager**: one Entra app shared by many Rails apps, with secret
  rotation that needs **no restart**. Static credentials work too.
- **Reliability**: cached access tokens, HTTP timeouts, short in-process retries for throttling
  and outages, and ActiveJob retries for `deliver_later`.
- **`MAIL_DELIVERY_METHOD` switch**: Microsoft Graph by default, SMTP as a rollback path.
- **Shared-mailbox From policy**: a default From of `"<App Name> <mailbox>"`, a helper for
  `"<Person> via <App Name>"`, and protection against Exchange `ErrorSendAsDenied`.
- **Rails integration**: Railtie, install generator, and `check` / `smoke` rake tasks.
- **PHI/PII-safe logging**: no secrets, tokens, recipients or message content in logs or errors.

Supports Ruby 3.1 – 3.4 and Rails 6.1 – 8.1 (CI: Ruby 3.1.2 + Rails 6.1.7, Ruby 3.4.8 + Rails 8.1).

Install from this repository:

```ruby
gem "ms_graph_mailer", github: "VandaPharma/ms_graph_mailer", tag: "v1.0.0"
```

> The module is `MsGraphMailer`, which the unrelated `ms-graph-mailer` gem also uses; don't install
> both in one application.

## Contents

- [Quick start](#quick-start)
- [How it works](#how-it-works)
- [Configuration](#configuration) (full reference: [docs/configuration.md](docs/configuration.md))
- [Sent Items: MIME vs JSON](#sent-items-mime-vs-json)
- [Sending on behalf of a person](#sending-on-behalf-of-a-person)
- [deliver_now and deliver_later](#deliver_now-and-deliver_later)
- [Switching to SMTP (rollback)](#switching-to-smtp-rollback)
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
   gem "ms_graph_mailer", github: "VandaPharma/ms_graph_mailer", tag: "v1.0.0"
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

     config.display_name     = -> { "My App" }
     config.set_default_from = true

     config.delivery_method    = ENV["MAIL_DELIVERY_METHOD"]   # unset = Graph in graph_environments
     config.graph_environments = %w[staging production]
     config.smtp_settings      = { address: "smtp.example.com", port: 587 } # rollback only
   end
   ```

5. Remove any `default from:` from `ApplicationMailer`, and any other initializer that sets
   `delivery_method` or `smtp_settings`.
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

Every option, with defaults, is in [docs/configuration.md](docs/configuration.md). The most important ones:

| Option | Default | Purpose |
|---|---|---|
| `user_id` | – (required) | Mailbox Graph sends from (same as `ms_graph_mailer`) |
| `save_to_sent_items` | `true` | `false` = no Sent Items copy (JSON send) |
| `tenant`, `client_id`, `client_secret` | `nil` | Entra app credentials given in the initializer |
| `aws_secret_id`, `aws_region`, `aws_secret_ttl` | `nil`, `nil`, `600` | Entra app credentials read from AWS Secrets Manager (instead of the above) |
| `credentials_provider` | `:auto` | Which of the two sources to use; `:auto` picks the one that is set (both set = boot error). `:static` / `:aws_secrets_manager` force one. |
| `display_name` | `nil` | From display name; string or callable evaluated per message |
| `set_default_from` | `false` | Set ActionMailer's default From to `"<display_name> <user_id>"` |
| `delivery_method` | `ENV["MAIL_DELIVERY_METHOD"]` | `"microsoft_graph"`, `"smtp"`, or `nil` (Graph in `graph_environments`) |
| `graph_environments` | `%w[production]` | Environments that use Graph when `delivery_method` is unset |
| `smtp_settings` | `nil` | Used when `delivery_method` is `"smtp"` |

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
  from: MsGraphMailer.from_on_behalf_of(user.full_name), # "Jane Doe via My App <notifications@example.com>"
  cc: user.email,
  reply_to: user.email,
  subject: email.subject
)
```

If a mailer sets any other From, `enforce_from` (default `true`) rewrites it the same way so
Exchange does not reject the message.

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

## Switching to SMTP (rollback)

```shell
MAIL_DELIVERY_METHOD=smtp   # then restart the web and job processes
```

`smtp_settings` must be configured. Unset the variable and restart to return to Graph.
In environments outside `graph_environments` with no variable set (typically development and
test), the gem leaves your existing delivery method (`letter_opener`, `:test`, ...) alone.

## Rake tasks

| Task | What it does |
|---|---|
| `bin/rails ms_graph_mailer:check` | Prints the active configuration, loads the credentials and requests a token. Sends nothing. Prints tenant and client IDs, never the secret. |
| `bin/rails "ms_graph_mailer:smoke[to@example.com]"` | Sends one test message with the default From |
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
