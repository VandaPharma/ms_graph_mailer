# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-10-22

### Added

- ActionMailer/Mail delivery method `:ms_graph` based on GitLab's `microsoft_graph_mailer` 0.1.0,
  with the same settings (`user_id`, `tenant`, `client_id`, `client_secret`, `azure_ad_endpoint`,
  `graph_endpoint`).
- `save_to_sent_items` setting: `true` sends MIME (as GitLab's 0.1.0), `false` sends JSON with
  `saveToSentItems: false`.
- Credentials providers: `:static` and `:aws_secrets_manager` (in-memory cache with TTL, reload on
  `invalid_client`, rotation without restart, last-good-value fallback), or a custom object.
- In-memory access token cache (no `oauth2` dependency).
- HTTP timeouts, in-process retries for throttling/5xx/connection failures, `TransientError`, and
  `ActionMailer::MailDeliveryJob.retry_on` for `deliver_later`.
- `MAIL_DELIVERY_METHOD` switch between Microsoft Graph and SMTP, with `graph_environments`.
- `display_name`, `set_default_from`, `enforce_from`, `default_from` and `from_on_behalf_of`.
- `MsGraphMailer.configure`, `ms_graph_mailer:install` generator, and `ms_graph_mailer:check` /
  `ms_graph_mailer:smoke` rake tasks.
- Support for Ruby 3.1–3.4 and Rails 6.1–8.1.

[Unreleased]: https://github.com/VandaPharma/ms_graph_mailer/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/VandaPharma/ms_graph_mailer/releases/tag/v1.0.0
