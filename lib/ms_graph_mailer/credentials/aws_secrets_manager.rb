# frozen_string_literal: true

require "json"
require "digest"

module MsGraphMailer
  module Credentials
    # Entra app credentials stored as a JSON secret in AWS Secrets Manager:
    #
    #   { "tenant_id": "...", "client_id": "...", "client_secret": "..." }
    #
    # AWS access uses access_key_id/secret_access_key (and optional session_token)
    # when given; otherwise the default AWS credential chain (e.g. an EC2 instance
    # role). The value is cached in process memory and re-read after `ttl` seconds,
    # or immediately via #refresh! when Entra rejects the cached secret, so rotating
    # the secret needs no application restart. The secret is never logged.
    class AwsSecretsManager
      DEFAULT_TTL   = 600
      FORCE_MIN_GAP = 30 # seconds between forced reloads

      @registry = {}
      @registry_mutex = Mutex.new

      class << self
        # One shared instance per secret, so the cache survives ActionMailer
        # building a new delivery object for every message.
        def for(secret_id:, region: nil, ttl: nil, access_key_id: nil, secret_access_key: nil,
                session_token: nil, error_notifier: nil, logger: nil)
          # Keyed by the AWS keys too (the secret key as a digest), so changed keys
          # get a new client instead of the cached one.
          key = [ secret_id, region, access_key_id, digest(secret_access_key), digest(session_token) ]
          @registry_mutex.synchronize do
            @registry[key] ||= new(secret_id: secret_id, region: region, ttl: ttl,
                                   access_key_id: access_key_id, secret_access_key: secret_access_key,
                                   session_token: session_token, error_notifier: error_notifier, logger: logger)
          end
        end

        def reset_registry!
          @registry_mutex.synchronize { @registry.clear }
        end

        private

        def digest(value)
          value.to_s.empty? ? nil : Digest::SHA256.hexdigest(value.to_s)
        end
      end

      attr_reader :secret_id, :region, :ttl

      def initialize(secret_id:, region: nil, ttl: nil, access_key_id: nil, secret_access_key: nil,
                     session_token: nil, client: nil, error_notifier: nil, logger: nil)
        raise ConfigurationError, "'aws_secret_id' is missing" if secret_id.to_s.strip.empty?
        if blank?(access_key_id) != blank?(secret_access_key)
          raise ConfigurationError, "Set both aws_access_key_id and aws_secret_access_key, or neither (to use the IAM role)"
        end

        @secret_id = secret_id
        @access_key_id = blank?(access_key_id) ? nil : access_key_id
        @secret_access_key = blank?(secret_access_key) ? nil : secret_access_key
        @session_token = blank?(session_token) ? nil : session_token
        @region = region
        @ttl = (ttl || DEFAULT_TTL).to_i
        @client = client
        @error_notifier = error_notifier
        @logger = logger
        @mutex = Mutex.new
        @value = nil
        @fetched_at = nil
        @forced_at = nil
      end

      def current
        @mutex.synchronize do
          load! if @value.nil? || monotonic - @fetched_at > ttl
          @value
        end
      end

      def refresh!
        @mutex.synchronize do
          return @value if @value && @forced_at && monotonic - @forced_at < FORCE_MIN_GAP

          @forced_at = monotonic
          load!
          @value
        end
      end

      # "access_keys" when keys were given, otherwise "default_chain" (IAM role etc.).
      def aws_credentials_source
        @access_key_id ? "access_keys" : "default_chain"
      end

      # The access key id with all but the last 4 characters masked, for diagnostics.
      def masked_access_key_id
        @access_key_id && "#{'*' * [ @access_key_id.length - 4, 0 ].max}#{@access_key_id[-4..]}"
      end

      private

      def load!
        raw = JSON.parse(client.get_secret_value(secret_id: secret_id).secret_string.to_s)
        @value = {
          tenant: raw["tenant_id"] || raw["tenant"],
          client_id: raw["client_id"],
          client_secret: raw["client_secret"]
        }.freeze
        missing = @value.select { |_, setting| setting.to_s.strip.empty? }.keys
        raise ConfigurationError, "Secret #{secret_id} is missing #{missing.join(', ')}" if missing.any?

        @fetched_at = monotonic
      rescue JSON::ParserError
        raise ConfigurationError, "Secret #{secret_id} is not valid JSON"
      rescue ConfigurationError
        raise
      rescue StandardError => e
        raise unless aws_error?(e)
        raise TransientError, "Could not read secret #{secret_id} (#{e.class})" if @value.nil?

        # Keep the last good credentials and try AWS again soon.
        @fetched_at = monotonic - ttl + FORCE_MIN_GAP
        @logger&.error("[ms_graph_mailer] Secrets Manager refresh failed, using cached credentials: #{e.class}")
        @error_notifier&.call(e, { secret_id: secret_id })
      end

      def aws_error?(error)
        (defined?(Aws::Errors::ServiceError) && error.is_a?(Aws::Errors::ServiceError)) ||
          (defined?(Seahorse::Client::NetworkingError) && error.is_a?(Seahorse::Client::NetworkingError)) ||
          (defined?(Aws::Errors::MissingCredentialsError) && error.is_a?(Aws::Errors::MissingCredentialsError))
      end

      def client
        @client ||= begin
          require "aws-sdk-secretsmanager"
          options = {}
          options[:region] = region if region
          if @access_key_id
            options[:credentials] = Aws::Credentials.new(@access_key_id, @secret_access_key, @session_token)
          end
          Aws::SecretsManager::Client.new(**options)
        rescue LoadError
          raise ConfigurationError,
                "credentials_provider :aws_secrets_manager needs the aws-sdk-secretsmanager gem; add it to your Gemfile"
        end
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def blank?(value)
        value.to_s.strip.empty?
      end
    end
  end
end
