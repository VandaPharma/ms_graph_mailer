# frozen_string_literal: true

require "mail"
require_relative "ms_graph_mailer/version"
require_relative "ms_graph_mailer/errors"
require_relative "ms_graph_mailer/delivery"
require_relative "ms_graph_mailer/configuration"
require_relative "ms_graph_mailer/diagnostics"
require_relative "ms_graph_mailer/railtie" if defined?(Rails::Railtie)

# Sends ActionMailer / Mail messages through Microsoft Graph sendMail.
# Based on GitLab's microsoft_graph_mailer 0.1.0 (MIT).
module MsGraphMailer
  DELIVERY_METHOD_NAME = :ms_graph

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
      @configured = true
      config
    end

    # True once configure has been called. Without it the gem behaves like GitLab's
    # 0.1.0: it only registers the :ms_graph delivery method.
    def configured?
      @configured ? true : false
    end

    # Test helper; also clears cached credentials and tokens.
    def reset!
      @config = nil
      @configured = false
      AccessToken.reset!
      Credentials::AwsSecretsManager.reset_registry!
    end

    # "App Name <shared-mailbox@example.com>", or the bare address without a display name.
    def default_from
      format_address(resolve(config.display_name))
    end

    # For mail written by a person but sent from the shared mailbox:
    # "Jane Doe via App Name <shared-mailbox@example.com>".
    def from_on_behalf_of(name)
      app_name = resolve(config.display_name)
      person = name.to_s.strip
      format_address([ (person unless person.empty?), app_name ].compact.join(" via "))
    end

    # "microsoft_graph", "smtp", or nil when the environment keeps its own setting.
    def delivery_method
      config.resolved_delivery_method(current_environment)
    end

    # Applies the configuration to ActionMailer::Base. Called by the Railtie once
    # ActionMailer loads, after the application's initializers have run.
    def apply!(base)
      config.validate!(current_environment)
      base.default(from: -> { MsGraphMailer.default_from }) if config.set_default_from

      case delivery_method
      when "smtp"
        base.delivery_method = :smtp
        base.smtp_settings = config.smtp_settings
      when "microsoft_graph"
        base.add_delivery_method(DELIVERY_METHOD_NAME, Delivery, config.delivery_settings)
        base.delivery_method = DELIVERY_METHOD_NAME
      end

      config.logger&.info(
        "[ms_graph_mailer] delivery_method=#{delivery_method || base.delivery_method} " \
        "user_id=#{config.user_id} save_to_sent_items=#{config.save_to_sent_items ? true : false}"
      )
    end

    # deliver_later only; deliver_now relies on the in-process retries in Delivery.
    def install_job_retries!
      return unless defined?(ActionMailer::MailDeliveryJob)
      return if config.job_retry_attempts.to_i <= 1

      errors =
        case delivery_method
        when "microsoft_graph" then [ TransientError ]
        when "smtp" then smtp_transient_errors
        end
      return if errors.nil? || errors.empty?

      ActionMailer::MailDeliveryJob.retry_on(*errors, wait: job_retry_wait, attempts: config.job_retry_attempts.to_i)
    end

    private

    def format_address(name)
      raise ConfigurationError, "user_id is not configured" if config.user_id.to_s.strip.empty?

      address = Mail::Address.new(config.user_id.to_s)
      address.display_name = name unless name.to_s.strip.empty?
      address.format
    end

    def resolve(value)
      value = value.call if value.respond_to?(:call)
      text = value.to_s.strip
      text.empty? ? nil : text
    end

    def current_environment
      defined?(Rails) && Rails.respond_to?(:env) ? Rails.env.to_s : ENV.fetch("RAILS_ENV", "development")
    end

    # :polynomially_longer was added in Rails 7.1; older versions call it :exponentially_longer.
    def job_retry_wait
      if defined?(ActiveJob) && ActiveJob.gem_version >= Gem::Version.new("7.1")
        :polynomially_longer
      else
        :exponentially_longer
      end
    end

    def smtp_transient_errors
      require "net/smtp"
      [ Net::SMTPServerBusy, Net::OpenTimeout ]
    end
  end
end
