# frozen_string_literal: true

module MsGraphMailer
  # Rails-level configuration, set in config/initializers/ms_graph_mailer.rb.
  # See docs/configuration.md for every option.
  class Configuration
    # --- Same settings as GitLab's microsoft_graph_mailer 0.1.0 ---
    attr_accessor :user_id, :tenant, :client_id, :client_secret, :azure_ad_endpoint, :graph_endpoint

    # --- Sent Items ---
    attr_accessor :save_to_sent_items

    # --- Credentials ---
    attr_accessor :credentials_provider, :aws_secret_id, :aws_region, :aws_secret_ttl
    # Optional AWS keys for reading the secret; without them the default AWS
    # credential chain (e.g. the EC2 instance role) is used.
    attr_accessor :aws_access_key_id, :aws_secret_access_key, :aws_session_token

    # --- From header ---
    attr_accessor :display_name, :enforce_from

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

      @credentials_provider = :auto
      @aws_secret_id = nil
      @aws_region = nil
      @aws_secret_ttl = Credentials::AwsSecretsManager::DEFAULT_TTL
      @aws_access_key_id = nil
      @aws_secret_access_key = nil
      @aws_session_token = nil

      @display_name = nil
      @enforce_from = true

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

    def validate!
      raise ConfigurationError, "user_id is required for Microsoft Graph delivery" if blank?(user_id)

      provider = credentials_provider
      return if provider.respond_to?(:current) && provider.respond_to?(:refresh!)

      unless Credentials::PROVIDERS.include?(provider.to_s) || provider.to_s.empty?
        raise ConfigurationError,
              "credentials_provider must be one of #{Credentials::PROVIDERS.join(', ')} (got #{provider.inspect})"
      end

      case Credentials.provider_name(delivery_settings)
      when "static"
        missing = { tenant: tenant, client_id: client_id, client_secret: client_secret }
                  .select { |_, value| blank?(value) }.keys
        raise ConfigurationError, "Static credentials are missing #{missing.join(', ')}" if missing.any?
      when "aws_secrets_manager"
        raise ConfigurationError, "aws_secret_id is required for credentials_provider :aws_secrets_manager" if blank?(aws_secret_id)
        if blank?(aws_access_key_id) != blank?(aws_secret_access_key)
          raise ConfigurationError, "Set both aws_access_key_id and aws_secret_access_key, or neither (to use the IAM role)"
        end
      end
    end

    # "static" or "aws_secrets_manager" (resolves :auto), or "custom" for a provider object.
    def resolved_credentials_provider
      provider = credentials_provider
      return "custom" if provider.respond_to?(:current) && provider.respond_to?(:refresh!)

      Credentials.provider_name(delivery_settings)
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
        aws_access_key_id: aws_access_key_id,
        aws_secret_access_key: aws_secret_access_key,
        aws_session_token: aws_session_token,
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
