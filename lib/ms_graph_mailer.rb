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

    # Configures Microsoft Graph delivery. In a Rails application, calling this makes
    # :ms_graph the ActionMailer delivery method; an application that should send
    # some other way (SMTP, letter_opener, :test) simply does not call it.
    def configure
      yield config
      @configured = true
      config
    end

    # True once configure has been called. Without it the gem only registers the
    # :ms_graph delivery method (for config.action_mailer.ms_graph_settings).
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

    # Validates the configuration and selects :ms_graph on ActionMailer::Base. Called
    # by the Railtie once ActionMailer loads, after the application's initializers.
    def apply!(base)
      config.validate!
      base.add_delivery_method(DELIVERY_METHOD_NAME, Delivery, config.delivery_settings)
      base.delivery_method = DELIVERY_METHOD_NAME

      config.logger&.info(
        "[ms_graph_mailer] delivery_method=#{DELIVERY_METHOD_NAME} user_id=#{config.user_id} " \
        "save_to_sent_items=#{config.save_to_sent_items ? true : false}"
      )
    end

    # deliver_later only; deliver_now relies on the in-process retries in Delivery.
    def install_job_retries!
      return unless defined?(ActionMailer::MailDeliveryJob)
      return if config.job_retry_attempts.to_i <= 1

      ActionMailer::MailDeliveryJob.retry_on(TransientError, wait: job_retry_wait, attempts: config.job_retry_attempts.to_i)
    end

    private

    # :polynomially_longer was added in Rails 7.1; older versions call it :exponentially_longer.
    def job_retry_wait
      if defined?(ActiveJob) && ActiveJob.gem_version >= Gem::Version.new("7.1")
        :polynomially_longer
      else
        :exponentially_longer
      end
    end
  end
end
