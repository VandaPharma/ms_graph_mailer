# Rails integration and multiple applications

The gem only handles Microsoft Graph. Your application decides **where** Graph is used and what
its mailers' **From** is; the gem sends whatever ActionMailer hands it through Graph.

## What the gem does at boot

1. When the gem loads, the `:ms_graph` delivery method is registered, so
   `config.action_mailer.delivery_method = :ms_graph` with
   `config.action_mailer.ms_graph_settings = {...}` also works without step 2.
2. Your initializer calls `MsGraphMailer.configure`. If it doesn't, the gem does nothing more.
3. After all initializers, when ActionMailer loads, the Railtie validates the configuration
   (raises `ConfigurationError` on a bad value), registers `:ms_graph` with the configured
   settings and makes it the delivery method, and logs one line (`user_id`,
   `save_to_sent_items`).
4. After initialization, it adds `retry_on` for transient Graph errors to
   `ActionMailer::MailDeliveryJob`.

Nothing contacts AWS or Microsoft at boot.

## Adding the gem to an application

1. Gemfile:

   ```ruby
   gem "ms_graph_mailer", github: "VandaPharma/ms_graph_mailer", branch: "main"
   gem "aws-sdk-secretsmanager", require: false # only when the credentials come from AWS Secrets Manager
   ```

2. `bin/rails generate ms_graph_mailer:install`, then edit the initializer, and decide in which
   environments it calls `configure` (below).
3. Make the mailers send From the `user_id` mailbox, e.g. in `ApplicationMailer`:

   ```ruby
   default from: -> { email_address_with_name("notifications@example.com", "My App") }
   ```

4. Mail written on behalf of a person: shared mailbox as From, the person in Cc and Reply-To
   (below).
5. Deploy, run `bin/rails ms_graph_mailer:check`, then `bin/rails "ms_graph_mailer:smoke[...]"`.

Rails 6.1 apps must use `ActionMailer::MailDeliveryJob` for `deliver_later` (the 6.1 default via
`load_defaults 6.1`, or `config.action_mailer.delivery_job = "ActionMailer::MailDeliveryJob"`).

## Graph in some environments, SMTP or others elsewhere

Calling `MsGraphMailer.configure` makes `:ms_graph` the delivery method, so wrap it in whatever
condition fits the application. A common setup: Graph in staging and production, an SMTP
fallback chosen by an environment variable, and development/test unchanged:

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
    config.user_id            = "notifications@example.com"
    config.save_to_sent_items = false
    config.aws_secret_id      = "shared/entra-mailer/#{Rails.env}"
    config.aws_region         = "us-east-1"
    config.display_name       = -> { "My App" }
  end
when nil
  # development keeps letter_opener, test keeps :test
else
  raise ArgumentError, "MAIL_DELIVERY_METHOD must be microsoft_graph or smtp (got #{mail_delivery_method.inspect})"
end
```

| `MAIL_DELIVERY_METHOD` | staging / production | development / test |
|---|---|---|
| unset | Microsoft Graph | unchanged |
| `microsoft_graph` | Microsoft Graph | Microsoft Graph |
| `smtp` | SMTP | SMTP |

Because the default From and the "on behalf of" From are set by the application, they are the same
whichever delivery method is active.

## Several applications, one Entra app, one shared mailbox

```
App A ─┐                                   ┌─ Entra app (Mail.Send scoped to sg-rails-mail-senders)
App B ─┼─ AWS Secrets Manager secret ──────┤
App C ─┘   (IAM role per app)              └─ shared mailbox notifications@example.com
```

Each application configures the same `user_id` and secret, and uses its own name in its default
From (`"App A" <notifications@example.com>`, `"App B" <notifications@example.com>`, ...), subject
to Exchange's display-name behaviour (see [runbooks.md](runbooks.md#first-live-test)). An
application can switch to its own mailbox later by changing `user_id` and its default From, and
adding that mailbox to the Exchange scope group.

Keep an eye on volume: Exchange Online and Graph limit sending per mailbox. The gem retries
throttling, but a high-volume app may need its own mailbox.

## Mail on behalf of a person

```ruby
class CustomerMailer < ApplicationMailer
  def message_from_staff(email)
    sender = email.user
    options = { to: email.recipient, subject: email.subject }
    if sender&.email.present?
      options[:from]     = email_address_with_name("notifications@example.com",
                                                   "#{sender.full_name.presence || sender.email} via My App")
      options[:cc]       = sender.email
      options[:reply_to] = sender.email
    end
    mail(options)
  end
end
```

The customer sees "Jane Doe via My App", Jane is copied, and replies go to Jane, over Graph or SMTP.
With `save_to_sent_items: false` nothing is stored in the shared mailbox; keep your own record of
what was sent (e.g. the `email` row) if you need one.

## Development and test

If the initializer does not call `configure` in development and test, those environments keep
their own delivery method (`letter_opener`, `:test`), so existing mailer tests continue to work.

To try Graph from a laptop without AWS access, set `MAIL_DELIVERY_METHOD=microsoft_graph` and give
the credentials in the initializer from environment variables; `credentials_provider` then selects
the initializer source whenever those variables are present:

```ruby
MsGraphMailer.configure do |config|
  config.user_id       = "notifications@example.com"
  config.aws_secret_id = "shared/entra-mailer/#{Rails.env}"
  config.aws_region    = "us-east-1"

  if ENV["ENTRA_CLIENT_SECRET"].present?
    config.credentials_provider = :static
    config.tenant        = ENV["ENTRA_TENANT_ID"]
    config.client_id     = ENV["ENTRA_CLIENT_ID"]
    config.client_secret = ENV["ENTRA_CLIENT_SECRET"]
  end
end
```
