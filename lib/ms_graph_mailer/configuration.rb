# frozen_string_literal: true

module MsGraphMailer
  # Rails-level configuration, set in config/initializers/ms_graph_mailer.rb.
  # See docs/configuration.md for every option.
  class Configuration
    DELIVERY_METHODS = %w[microsoft_graph smtp].freeze
    CREDENTIALS_PROVIDERS = %w[static aws_secrets_manager].freeze

    # --- Same settings as GitLab's microsoft_graph_mailer 0.1.0 ---
    attr_accessor :user_id, :tenant, :client_id, :client_secret, :azure_ad_endpoint, :graph_endpoint

    # --- Sent Items ---
    attr_accessor :save_to_sent_items

    # --- Credentials ---
    attr_accessor :credentials_provider, :aws_secret_id, :aws_region, :aws_secret_ttl

    # --- From header ---
    attr_accessor :display_name, :set_default_from, :enforce_from

    # --- Delivery switch ---
    attr_accessor :delivery_method, :graph_environments, :smtp_settings

    # --- Reliability ---
    attr_accessor :open_timeout, :read_timeout, :max_transient_retries, :max_retry_sleep, :job_retry_attempts

    # --- Observability ---
    attr_writer :logger
    attr_accessor :error_notifier

    def initialize
      @user_id = nil
      @tenant = nil
      @client_id = nil
      @client_secret = nil
      @azure_ad_endpoint = Delivery::DEFAULTS[:azure_ad_endpoint]
      @graph_endpoint = Delivery::DEFAULTS[:graph_endpoint]

      @save_to_sent_items = true

      @credentials_provider = :static
      @aws_secret_id = nil
      @aws_region = nil
      @aws_secret_ttl = Credentials::AwsSecretsManager::DEFAULT_TTL

      @display_name = nil
      @set_default_from = false
      @enforce_from = true

      @delivery_method = ENV["MAIL_DELIVERY_METHOD"]
      @graph_environments = %w[production]
      @smtp_settings = nil

      @open_timeout = Delivery::DEFAULTS[:open_timeout]
      @read_timeout = Delivery::DEFAULTS[:read_timeout]
      @max_transient_retries = Delivery::DEFAULTS[:max_transient_retries]
      @max_retry_sleep = Delivery::DEFAULTS[:max_retry_sleep]
      @job_retry_attempts = 5

      @logger = nil
      @error_notifier = default_error_notifier
    end

    def logger
      @logger || (defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : nil)
    end

    # "microsoft_graph", "smtp", or nil (leave the environment's own delivery method alone).
    def resolved_delivery_method(environment)
      requested = delivery_method.to_s.strip.downcase
      return requested unless requested.empty?

      "microsoft_graph" if Array(graph_environments).map(&:to_s).include?(environment.to_s)
    end

    def validate!(environment)
      method = resolved_delivery_method(environment)
      case method
      when nil
        nil
      when "smtp"
        if smtp_settings.nil? || smtp_settings.empty?
          raise ConfigurationError, "MAIL_DELIVERY_METHOD is smtp but smtp_settings is not configured"
        end
      when "microsoft_graph"
        validate_graph!
      else
        raise ConfigurationError,
              "delivery_method must be one of #{DELIVERY_METHODS.join(', ')} (got #{method.inspect})"
      end
    end

    # Settings hash handed to MsGraphMailer::Delivery.
    def delivery_settings
      {
        user_id: user_id,
        tenant: tenant,
        client_id: client_id,
        client_secret: client_secret,
        azure_ad_endpoint: azure_ad_endpoint,
        graph_endpoint: graph_endpoint,
        save_to_sent_items: save_to_sent_items,
        credentials_provider: credentials_provider,
        aws_secret_id: aws_secret_id,
        aws_region: aws_region,
        aws_secret_ttl: aws_secret_ttl,
        display_name: display_name,
        enforce_from: enforce_from,
        open_timeout: open_timeout,
        read_timeout: read_timeout,
        max_transient_retries: max_transient_retries,
        max_retry_sleep: max_retry_sleep,
        logger: logger,
        error_notifier: error_notifier
      }
    end

    private

    def validate_graph!
      raise ConfigurationError, "user_id is required for Microsoft Graph delivery" if blank?(user_id)

      provider = credentials_provider
      return if provider.respond_to?(:current) && provider.respond_to?(:refresh!)

      case provider.to_s
      when "static"
        missing = { tenant: tenant, client_id: client_id, client_secret: client_secret }
                  .select { |_, value| blank?(value) }.keys
        raise ConfigurationError, "Static credentials are missing #{missing.join(', ')}" if missing.any?
      when "aws_secrets_manager"
        raise ConfigurationError, "aws_secret_id is required for credentials_provider :aws_secrets_manager" if blank?(aws_secret_id)
      else
        raise ConfigurationError,
              "credentials_provider must be one of #{CREDENTIALS_PROVIDERS.join(', ')} (got #{provider.inspect})"
      end
    end

    def default_error_notifier
      lambda do |error, context|
        Honeybadger.notify(error, context: context) if defined?(Honeybadger) && Honeybadger.respond_to?(:notify)
      end
    end

    def blank?(value)
      value.to_s.strip.empty?
    end
  end
end
