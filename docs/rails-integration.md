# Rails integration and multiple applications

## What the gem does at boot

1. When the gem loads, the `:ms_graph` delivery method is registered, so
   `config.action_mailer.delivery_method = :ms_graph` with
   `config.action_mailer.ms_graph_settings = {...}` also works without step 2.
2. Your initializer calls `MsGraphMailer.configure`. Without it, the gem does nothing more.
3. After all initializers, when ActionMailer loads, the Railtie:
   - validates the configuration (raises `ConfigurationError` on a bad value);
   - sets `ActionMailer::Base.default from:` when `set_default_from` is `true`;
   - selects `:ms_graph` with the configured settings, or selects `:smtp`, or
     leaves the environment's delivery method alone (see the
     [switch table](configuration.md#delivery-method-switch));
   - logs one line: delivery method, `user_id`, `save_to_sent_items`.
4. After initialization, it adds `retry_on` to `ActionMailer::MailDeliveryJob` for transient errors.

Nothing contacts AWS or Microsoft at boot.

## Adding the gem to an application

1. Gemfile (always with the `github:` source):

   ```ruby
   gem "ms_graph_mailer", github: "VandaPharma/ms_graph_mailer", tag: "v1.0.0"
   gem "aws-sdk-secretsmanager", require: false # only when the credentials come from AWS Secrets Manager
   ```

2. `bin/rails generate ms_graph_mailer:install`, then edit the initializer.
3. Remove what the gem now handles:
   - any initializer or environment setting of `delivery_method` / `smtp_settings` for the
     environments the gem manages (keep development's `letter_opener` and test's `:test`);
   - `default from:` in `ApplicationMailer`, when `set_default_from` is `true`.
4. Mail written on behalf of a person: use `from_on_behalf_of`, `cc` and `reply_to` (below).
5. Deploy with `MAIL_DELIVERY_METHOD=smtp`, run `ms_graph_mailer:check`, unset the
   variable, restart, run `ms_graph_mailer:smoke[...]`.

Rails 6.1 apps must use `ActionMailer::MailDeliveryJob` for `deliver_later` (the 6.1 default via
`load_defaults 6.1`, or `config.action_mailer.delivery_job = "ActionMailer::MailDeliveryJob"`).

## Several applications, one Entra app, one shared mailbox

```
App A ─┐                                   ┌─ Entra app (Mail.Send scoped to sg-rails-mail-senders)
App B ─┼─ AWS Secrets Manager secret ──────┤
App C ─┘   (IAM role per app)              └─ shared mailbox notifications@example.com
```

Each application's initializer differs only in `display_name` (and any legacy `smtp_settings`):

```ruby
MsGraphMailer.configure do |config|
  config.user_id              = "notifications@example.com"
  config.save_to_sent_items   = false
  config.aws_secret_id        = "shared/entra-mailer/#{Rails.env}"
  config.aws_region           = "us-east-1"
  config.display_name         = -> { "App A" }           # or a value from the app's own settings
  config.set_default_from     = true
  config.graph_environments   = %w[staging production]
end
```

Recipients see `"App A" <notifications@example.com>`, `"App B" <notifications@example.com>`, ...
(subject to Exchange's display-name behaviour, see [runbooks.md](runbooks.md#first-live-test)).
An application can switch to its own mailbox later by changing `user_id` and adding that mailbox
to the Exchange scope group; no code change.

Keep an eye on volume: Exchange Online and Graph limit sending per mailbox. The gem retries
throttling, but a high-volume app may need its own mailbox.

## Mail on behalf of a person

```ruby
class CustomerMailer < ApplicationMailer
  def message_from_staff(email)
    sender = email.user
    options = { to: email.recipient, subject: email.subject }
    if sender&.email.present?
      options[:from]     = MsGraphMailer.from_on_behalf_of(sender.full_name.presence || sender.email)
      options[:cc]       = sender.email
      options[:reply_to] = sender.email
    end
    mail(options)
  end
end
```

The customer sees "Jane Doe via App A", Jane is copied, and replies go to Jane. With
`save_to_sent_items: false` nothing is stored in the shared mailbox; keep your own record of
what was sent (e.g. the `email` row) if you need one.

## Development and test

With the variable unset and those environments outside `graph_environments`, development keeps
`letter_opener` (or whatever it uses) and test keeps `:test`, so existing mailer tests continue to
work. The default From (when `set_default_from` is on) applies in every environment.

To try Graph from a laptop without AWS access, give the credentials in the initializer from
environment variables and set `MAIL_DELIVERY_METHOD=microsoft_graph`. `credentials_provider`
then selects the initializer source whenever those variables are present:

```ruby
config.aws_secret_id = "shared/entra-mailer/#{Rails.env}"
config.aws_region    = "us-east-1"

if ENV["ENTRA_CLIENT_SECRET"].present?
  config.credentials_provider = :static
  config.tenant        = ENV["ENTRA_TENANT_ID"]
  config.client_id     = ENV["ENTRA_CLIENT_ID"]
  config.client_secret = ENV["ENTRA_CLIENT_SECRET"]
end
```
