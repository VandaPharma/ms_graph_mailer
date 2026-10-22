# frozen_string_literal: true

module MsGraphMailer
  # Where the Entra app credentials (tenant, client_id, client_secret) come from:
  # the settings themselves (:static) or AWS Secrets Manager (:aws_secrets_manager).
  module Credentials
    PROVIDERS = %w[auto static aws_secrets_manager].freeze
    STATIC_KEYS = %i[tenant client_id client_secret].freeze

    class << self
      # Provider name for the given settings. With credentials_provider :auto (the
      # default) it is :static when tenant/client_id/client_secret are set and
      # :aws_secrets_manager when aws_secret_id is set.
      def provider_name(settings)
        name = settings[:credentials_provider].to_s
        return name unless name.empty? || name == "auto"

        static = STATIC_KEYS.any? { |key| present?(settings[key]) }
        aws = present?(settings[:aws_secret_id])

        if static && aws
          raise ConfigurationError,
                "Both tenant/client_id/client_secret and aws_secret_id are set; remove one or set " \
                "credentials_provider to :static or :aws_secrets_manager"
        end
        return "static" if static
        return "aws_secrets_manager" if aws

        raise ConfigurationError,
              "Entra app credentials are missing: set tenant, client_id and client_secret, or aws_secret_id"
      end

      private

      def present?(value)
        !value.to_s.strip.empty?
      end
    end
  end
end
