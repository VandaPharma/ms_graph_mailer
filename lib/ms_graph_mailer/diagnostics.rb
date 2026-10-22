# frozen_string_literal: true

require "time"

module MsGraphMailer
  # Backs the rake tasks. Output never includes the client secret, access tokens
  # or message content.
  module Diagnostics
    class << self
      # Prints the active configuration and, when Graph delivery is configured, loads
      # the credentials and requests a token. Sends nothing.
      def check(out: $stdout)
        out.puts "delivery_method:      #{action_mailer_method}"
        unless MsGraphMailer.configured?
          out.puts "ms_graph_mailer:      not configured (MsGraphMailer.configure was not called)"
          return true
        end

        config = MsGraphMailer.config
        provider = config.resolved_credentials_provider
        out.puts "user_id:              #{config.user_id}"
        out.puts "save_to_sent_items:   #{config.save_to_sent_items ? true : false}"
        out.puts "credentials_provider: #{provider}#{' (auto)' if config.credentials_provider.to_s == 'auto'}"
        out.puts "aws_secret_id:        #{config.aws_secret_id} (#{config.aws_region || 'default region'})" if provider == "aws_secrets_manager"

        delivery = Delivery.new(config.delivery_settings)
        credentials = delivery.send(:credentials).current
        out.puts "tenant:               #{credentials[:tenant]}"
        out.puts "client_id:            #{credentials[:client_id]}"
        AccessToken.fetch(delivery.send(:client), credentials)
        out.puts "token:                OK"
        true
      end

      # Sends one message through the application's delivery method, using its
      # default From. With display_name, the From is "<display_name>" on the
      # user_id mailbox, to check which sender name recipients actually see.
      def smoke(to:, display_name: nil, out: $stdout)
        raise ArgumentError, "usage: rake \"ms_graph_mailer:smoke[to@example.com,Optional Name]\"" if to.to_s.strip.empty?

        from = nil
        unless display_name.to_s.strip.empty?
          raise ConfigurationError, "display_name needs MsGraphMailer.configure with user_id" if MsGraphMailer.config.user_id.to_s.strip.empty?

          address = Mail::Address.new(MsGraphMailer.config.user_id.to_s)
          address.display_name = display_name.to_s.strip
          from = address.format
        end
        message = smoke_mailer.smoke(to: to, from: from).deliver_now
        out.puts "Sent test message from #{message[:from]} to #{to} via #{action_mailer_method}"
        true
      end

      private

      def smoke_mailer
        return SmokeMailer if defined?(SmokeMailer)

        # Inherit the application's defaults (e.g. its default From) when it has an ApplicationMailer.
        parent = defined?(::ApplicationMailer) ? ::ApplicationMailer : ActionMailer::Base
        mailer = Class.new(parent) do
          def smoke(to:, from:)
            options = {
              to: to,
              subject: "ms_graph_mailer test message",
              content_type: "text/html",
              body: "<p>Test message sent at #{Time.now.utc.iso8601} by ms_graph_mailer.</p>"
            }
            options[:from] = from if from
            mail(options)
          end
        end
        MsGraphMailer.const_set(:SmokeMailer, mailer)
      end

      def action_mailer_method
        defined?(ActionMailer::Base) ? ActionMailer::Base.delivery_method : "unknown"
      end
    end
  end
end
