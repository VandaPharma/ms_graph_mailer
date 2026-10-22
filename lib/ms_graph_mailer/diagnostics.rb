# frozen_string_literal: true

require "time"

module MsGraphMailer
  # Backs the rake tasks. Output never includes the client secret, access tokens
  # or message content.
  module Diagnostics
    class << self
      # Prints the active configuration and, for Graph delivery, loads the
      # credentials and requests a token. Sends nothing.
      def check(out: $stdout)
        config = MsGraphMailer.config
        method = MsGraphMailer.delivery_method

        out.puts "delivery_method:      #{method || "(environment default: #{action_mailer_method})"}"
        out.puts "user_id:              #{config.user_id}"
        out.puts "default_from:         #{safe { MsGraphMailer.default_from }}"
        out.puts "set_default_from:     #{config.set_default_from ? true : false}"
        out.puts "save_to_sent_items:   #{config.save_to_sent_items ? true : false}"
        return true unless method == "microsoft_graph"

        provider = config.resolved_credentials_provider
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

      # Sends one message through the configured delivery method. With
      # display_name, the From name is "<display_name>" on the shared mailbox,
      # to check which sender name recipients actually see.
      def smoke(to:, display_name: nil, out: $stdout)
        raise ArgumentError, "usage: rake \"ms_graph_mailer:smoke[to@example.com,Optional Name]\"" if to.to_s.strip.empty?

        from = if display_name.to_s.strip.empty?
                 MsGraphMailer.default_from
               else
                 address = Mail::Address.new(MsGraphMailer.config.user_id.to_s)
                 address.display_name = display_name.to_s.strip
                 address.format
               end
        smoke_mailer.smoke(to: to, from: from).deliver_now
        out.puts "Sent test message from #{from} to #{to} via #{action_mailer_method}"
        true
      end

      private

      def smoke_mailer
        return SmokeMailer if defined?(SmokeMailer)

        mailer = Class.new(ActionMailer::Base) do
          def smoke(to:, from:)
            mail(
              to: to,
              from: from,
              subject: "ms_graph_mailer test message",
              content_type: "text/html",
              body: "<p>Test message sent at #{Time.now.utc.iso8601} by ms_graph_mailer.</p>"
            )
          end
        end
        MsGraphMailer.const_set(:SmokeMailer, mailer)
      end

      def action_mailer_method
        defined?(ActionMailer::Base) ? ActionMailer::Base.delivery_method : "unknown"
      end

      def safe
        yield
      rescue StandardError => e
        "(#{e.message})"
      end
    end
  end
end
