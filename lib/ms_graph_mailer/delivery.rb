# frozen_string_literal: true

require "mail"
require_relative "errors"
require_relative "client"
require_relative "access_token"
require_relative "message_builder"
require_relative "credentials"
require_relative "credentials/static"
require_relative "credentials/aws_secrets_manager"

module MsGraphMailer
  # Mail / ActionMailer delivery method that sends through Microsoft Graph.
  # Accepts the same settings as GitLab's microsoft_graph_mailer 0.1.0 (user_id, tenant,
  # client_id, client_secret, azure_ad_endpoint, graph_endpoint) plus the options
  # documented in the README, and can be used without Rails:
  #
  #   MsGraphMailer::Delivery.new(user_id: "...", tenant: "...",
  #     client_id: "...", client_secret: "...", save_to_sent_items: false).deliver!(mail)
  class Delivery
    DEFAULTS = {
      azure_ad_endpoint: "https://login.microsoftonline.com",
      graph_endpoint: "https://graph.microsoft.com",
      save_to_sent_items: true,
      credentials_provider: :auto,
      enforce_from: true,
      open_timeout: 5,
      read_timeout: 20,
      max_transient_retries: 2,
      max_retry_sleep: 2
    }.freeze

    CREDENTIAL_ERRORS = %w[invalid_client unauthorized_client].freeze

    attr_reader :settings
    alias ms_graph_settings settings

    def initialize(settings)
      @settings = DEFAULTS.merge(settings.to_h.transform_keys(&:to_sym))
      raise ConfigurationError, "'user_id' is missing" if user_id.to_s.strip.empty?

      @credentials = build_credentials
      @client = Client.new(
        azure_ad_endpoint: @settings[:azure_ad_endpoint],
        graph_endpoint: @settings[:graph_endpoint],
        open_timeout: @settings[:open_timeout],
        read_timeout: @settings[:read_timeout]
      )
    end

    def deliver!(message)
      enforce_from!(message) if settings[:enforce_from] && user_id.to_s.include?("@")

      with_auth_refresh do
        with_transient_retries { send_message(message) }
      end
    end

    private

    attr_reader :credentials, :client

    def user_id
      settings[:user_id]
    end

    def logger
      settings[:logger]
    end

    def send_message(message)
      token = AccessToken.fetch(@client, @credentials.current)

      if settings[:save_to_sent_items]
        @client.send_mime(user_id, encoded_with_bcc(message), token)
      else
        @client.send_json(user_id, MessageBuilder.new(message).to_graph, token, save_to_sent_items: false)
      end
    end

    # Graph sends as the user_id mailbox. A different From would be rejected by
    # Exchange (ErrorSendAsDenied), so send as the mailbox while keeping the
    # original name visible ("Jane Doe via App") and replies going to it.
    def enforce_from!(message)
      original = message[:from]&.addrs&.first
      return if original && original.address.to_s.casecmp?(user_id.to_s)

      app_name = resolved_display_name
      name =
        if original
          message.reply_to = original.address if Array(message.reply_to).empty?
          logger&.warn("[ms_graph_mailer] From #{original.address} sent as #{user_id}")
          [ blank_to_nil(original.display_name) || original.address, app_name ].compact.join(" via ")
        else
          app_name
        end

      address = Mail::Address.new(user_id.to_s)
      address.display_name = name if name
      message.from = address.format
    end

    def resolved_display_name
      value = settings[:display_name]
      value = value.call if value.respond_to?(:call)
      blank_to_nil(value&.to_s)
    end

    # Same as ms_graph_mailer: Mail leaves Bcc out of encoded output unless told otherwise.
    # https://github.com/mikel/mail/pull/872
    def encoded_with_bcc(message)
      bcc = message[:bcc]
      previous = bcc&.include_in_headers
      bcc.include_in_headers = true if bcc
      message.encoded
    ensure
      bcc.include_in_headers = previous if bcc
    end

    # invalid_client: the secret was rotated or revoked, so reload it.
    # 401 from Graph: the cached token is no longer accepted, so get a new one.
    def with_auth_refresh
      yield
    rescue TransientError
      raise
    rescue DeliveryError => e
      if CREDENTIAL_ERRORS.include?(e.code)
        logger&.warn("[ms_graph_mailer] Entra rejected the cached credentials (#{e.code}); reloading")
        AccessToken.invalidate(@client, @credentials.current)
        @credentials.refresh!
      elsif e.status == 401
        AccessToken.invalidate(@client, @credentials.current)
      else
        raise
      end
      yield
    end

    def with_transient_retries
      attempts = 0
      begin
        yield
      rescue TransientError => e
        attempts += 1
        raise if attempts > settings[:max_transient_retries].to_i

        pause((e.retry_after || 1).clamp(1, [ settings[:max_retry_sleep].to_i, 1 ].max))
        retry
      end
    end

    def pause(seconds)
      sleep(seconds)
    end

    def build_credentials
      provider = settings[:credentials_provider]
      return provider if provider.respond_to?(:current) && provider.respond_to?(:refresh!)

      case Credentials.provider_name(settings)
      when "static"
        Credentials::Static.new(tenant: settings[:tenant], client_id: settings[:client_id],
                                client_secret: settings[:client_secret])
      when "aws_secrets_manager"
        Credentials::AwsSecretsManager.for(
          secret_id: settings[:aws_secret_id], region: settings[:aws_region], ttl: settings[:aws_secret_ttl],
          error_notifier: settings[:error_notifier], logger: logger
        )
      else
        raise ConfigurationError, "Unknown credentials_provider #{provider.inspect} (use :auto, :static or :aws_secrets_manager)"
      end
    end

    def blank_to_nil(value)
      value.to_s.strip.empty? ? nil : value
    end
  end
end
