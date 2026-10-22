# frozen_string_literal: true

require "digest"

module MsGraphMailer
  # Client-credentials access tokens, cached in process memory until shortly
  # before they expire. Keyed by endpoint, tenant, client id and a digest of the
  # secret, so a rotated secret automatically gets a new token.
  module AccessToken
    EXPIRY_MARGIN = 300 # seconds

    @mutex = Mutex.new
    @tokens = {}

    class << self
      def fetch(client, credentials)
        key = cache_key(client, credentials)
        @mutex.synchronize do
          token, expires_at = @tokens[key]
          return token if token && monotonic < expires_at

          token, expires_in = client.request_token(credentials)
          @tokens[key] = [ token, monotonic + [ expires_in.to_i - EXPIRY_MARGIN, 0 ].max ]
          token
        end
      end

      def invalidate(client, credentials)
        key = cache_key(client, credentials)
        @mutex.synchronize { @tokens.delete(key) }
      end

      def reset!
        @mutex.synchronize { @tokens.clear }
      end

      private

      def cache_key(client, credentials)
        [
          client.azure_ad_endpoint,
          client.graph_endpoint,
          credentials[:tenant],
          credentials[:client_id],
          Digest::SHA256.hexdigest(credentials[:client_secret].to_s)
        ]
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
