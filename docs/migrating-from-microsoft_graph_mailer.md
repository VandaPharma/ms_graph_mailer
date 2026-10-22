# Migrating from GitLab's microsoft_graph_mailer 0.1.0

`ms_graph_mailer` is based on GitLab's `microsoft_graph_mailer` 0.1.0. The settings have the same
names and meaning, and the default `save_to_sent_items: true` sends the same MIME request, so
switching means renaming the gem, the module and the delivery method.

| GitLab's microsoft_graph_mailer 0.1.0 | ms_graph_mailer |
|---|---|
| `gem "microsoft_graph_mailer"` | `gem "ms_graph_mailer", github: "VandaPharma/ms_graph_mailer", branch: "main"` |
| `config.action_mailer.delivery_method = :microsoft_graph` | `config.action_mailer.delivery_method = :ms_graph`, or let the gem set it from `MsGraphMailer.configure` |
| `config.action_mailer.microsoft_graph_settings = { user_id:, tenant:, client_id:, client_secret:, azure_ad_endpoint:, graph_endpoint: }` | `config.action_mailer.ms_graph_settings = { ... }` with the same keys, or `MsGraphMailer.configure` |
| `MicrosoftGraphMailer::Delivery.new(settings)` | `MsGraphMailer::Delivery.new(settings)` (same keys) |
| `MicrosoftGraphMailer::Error`, `ConfigurationError`, `DeliveryError` | `MsGraphMailer::Error`, `ConfigurationError`, `DeliveryError`, plus `TransientError` (a `DeliveryError`) with `#status`, `#code`, `#retry_after` |
| Depends on `oauth2` | No `oauth2` dependency (uses `Net::HTTP`) |
| New token for every message | Token cached in memory until near expiry |

## Steps

1. Gemfile: replace `gem "microsoft_graph_mailer"` with

   ```ruby
   gem "ms_graph_mailer", github: "VandaPharma/ms_graph_mailer", branch: "main"
   ```

2. Quickest switch: in your environment files, rename `:microsoft_graph` to `:ms_graph` and
   `microsoft_graph_settings` to `ms_graph_settings`. Rename `MicrosoftGraphMailer::` to
   `MsGraphMailer::` wherever your code references it (e.g. `rescue` clauses).
3. Recommended: run `bin/rails generate ms_graph_mailer:install`, move the settings into
   `MsGraphMailer.configure`, and remove them from the environment files. That enables AWS
   Secrets Manager credentials, `save_to_sent_items = false`, job retries and the rake tasks.
   Like GitLab's gem, this gem only handles Graph: choosing SMTP elsewhere and the mailers'
   default From stay in your application.

## Behaviour differences to note

- `enforce_from` (default on) rewrites a From that is not `user_id` instead of letting Exchange
  reject it. Pass `enforce_from: false` in the settings to keep the old behaviour.
- Throttling, 5xx responses and failed connections are retried briefly in-process; GitLab's 0.1.0
  raised immediately. Retries of `deliver_later` jobs are only added when the gem is configured
  through `MsGraphMailer.configure`.
- Read timeouts raise `DeliveryError` (no retry), so a message Graph may have accepted is not sent
  twice.
