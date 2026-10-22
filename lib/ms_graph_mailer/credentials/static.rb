# frozen_string_literal: true

module MsGraphMailer
  module Credentials
    # Credentials given directly in settings, as in GitLab's microsoft_graph_mailer 0.1.0.
    class Static
      def initialize(tenant:, client_id:, client_secret:)
        @value = { tenant: tenant, client_id: client_id, client_secret: client_secret }.freeze

        @value.each do |key, setting|
          raise ConfigurationError, "'#{key}' is missing" if setting.to_s.strip.empty?
        end
      end

      def current
        @value
      end

      # Static credentials cannot change at runtime.
      def refresh!
        @value
      end
    end
  end
end
