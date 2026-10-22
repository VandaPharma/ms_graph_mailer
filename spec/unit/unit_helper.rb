# frozen_string_literal: true

require "ms_graph_mailer"
require "aws-sdk-secretsmanager"

module UnitHelpers
  def base_settings(overrides = {})
    {
      user_id: "notifications@example.com",
      tenant: "tenant-id",
      client_id: "client-id",
      client_secret: "client-secret",
      max_retry_sleep: 1
    }.merge(overrides)
  end

  def build_mail(**fields)
    defaults = {
      from: "App <notifications@example.com>",
      to: "patient@example.org",
      subject: "Hello",
      html: "<p>Hi</p>"
    }
    fields = defaults.merge(fields)
    Mail.new do
      from fields[:from] if fields[:from]
      to fields[:to]
      cc fields[:cc] if fields[:cc]
      bcc fields[:bcc] if fields[:bcc]
      reply_to fields[:reply_to] if fields[:reply_to]
      subject fields[:subject]
      html_part do
        content_type "text/html; charset=UTF-8"
        body fields[:html]
      end
      text_part { body "Hi" } if fields[:text]
    end
  end

  def delivery(overrides = {})
    MsGraphMailer::Delivery.new(base_settings(overrides)).tap do |d|
      allow(d).to receive(:pause)
    end
  end
end

RSpec.configure do |config|
  config.include UnitHelpers
  config.before { MsGraphMailer.reset! }
end
