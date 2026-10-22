# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "erb"

module MsGraphMailer
  # Minimal Microsoft Graph HTTP client: OAuth 2.0 client-credentials token and
  # user sendMail, in MIME (as GitLab's microsoft_graph_mailer 0.1.0) or JSON form.
  #
  # https://learn.microsoft.com/graph/api/user-sendmail
  # https://learn.microsoft.com/entra/identity-platform/v2-oauth2-client-creds-grant-flow
  class Client
    MAX_REQUEST_BYTES  = 4_000_000 # Graph's limit for a single sendMail request
    TRANSIENT_STATUSES = [ 429, 500, 502, 503, 504 ].freeze
    CONNECTION_ERRORS  = [
      Net::OpenTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
      Errno::ENETUNREACH, SocketError
    ].freeze

    attr_reader :azure_ad_endpoint, :graph_endpoint

    def initialize(azure_ad_endpoint:, graph_endpoint:, open_timeout:, read_timeout:)
      @azure_ad_endpoint = azure_ad_endpoint.to_s.chomp("/")
      @graph_endpoint = graph_endpoint.to_s.chomp("/")
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    # Returns [access_token, expires_in_seconds].
    def request_token(credentials)
      uri = URI("#{azure_ad_endpoint}/#{credentials[:tenant]}/oauth2/v2.0/token")
      request = Net::HTTP::Post.new(uri)
      request.set_form_data(
        client_id: credentials[:client_id],
        client_secret: credentials[:client_secret],
        grant_type: "client_credentials",
        scope: "#{graph_endpoint}/.default"
      )
      body = parse(perform(uri, request).body)
      token = body["access_token"]
      raise DeliveryError, "Token response from #{uri.host} has no access_token" if token.to_s.empty?

      [ token, (body["expires_in"] || 3600).to_i ]
    end

    # Same request as GitLab's microsoft_graph_mailer 0.1.0. Graph always keeps a copy in Sent Items.
    def send_mime(user_id, message_in_mime_format, access_token)
      request = Net::HTTP::Post.new(send_mail_uri(user_id), "Authorization" => "Bearer #{access_token}",
                                                            "Content-Type" => "text/plain")
      request.body = [ message_in_mime_format ].pack("m0")
      submit(request)
    end

    # JSON form; the only form that accepts saveToSentItems.
    def send_json(user_id, message, access_token, save_to_sent_items:)
      request = Net::HTTP::Post.new(send_mail_uri(user_id), "Authorization" => "Bearer #{access_token}",
                                                            "Content-Type" => "application/json")
      request.body = JSON.generate({ message: message, saveToSentItems: save_to_sent_items ? true : false })
      submit(request)
    end

    private

    def send_mail_uri(user_id)
      URI("#{graph_endpoint}/v1.0/users/#{ERB::Util.url_encode(user_id.to_s).gsub('%40', '@')}/sendMail")
    end

    def submit(request)
      if request.body.bytesize > MAX_REQUEST_BYTES
        raise DeliveryError, "Message is #{request.body.bytesize} bytes; Graph accepts up to #{MAX_REQUEST_BYTES} per request"
      end

      perform(request.uri, request)
    end

    def perform(uri, request)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                 open_timeout: @open_timeout, read_timeout: @read_timeout) do |http|
        http.request(request)
      end
      return response if response.is_a?(Net::HTTPSuccess)

      raise error_for(uri, response)
    rescue *CONNECTION_ERRORS => e
      raise TransientError, "Connection to #{uri.host} failed (#{e.class})"
    rescue Net::ReadTimeout
      # The request may have been processed (e.g. the message accepted), so this
      # is not treated as safe to retry.
      raise DeliveryError, "Timed out waiting for #{uri.host}"
    end

    # Graph errors look like {"error": {"code": "..."}}; token endpoint errors like
    # {"error": "invalid_client"}. Messages carry status and code only, never bodies.
    def error_for(uri, response)
      status = response.code.to_i
      error = parse(response.body)["error"]
      code = error.is_a?(Hash) ? error["code"] : error
      message = "#{uri.host} returned #{status}#{" #{code}" if code}"

      if TRANSIENT_STATUSES.include?(status)
        retry_after = response["Retry-After"].to_s[/\A\d+\z/]&.to_i
        TransientError.new(message, status: status, code: code, retry_after: retry_after)
      else
        DeliveryError.new(message, status: status, code: code)
      end
    end

    def parse(body)
      parsed = JSON.parse(body.to_s.empty? ? "{}" : body)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end
  end
end
