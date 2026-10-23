# frozen_string_literal: true

require_relative "unit_helper"

RSpec.describe MsGraphMailer::Delivery do
  describe "settings" do
    it "requires user_id, like GitLab's 0.1.0" do
      expect { described_class.new(base_settings(user_id: nil)) }
        .to raise_error(MsGraphMailer::ConfigurationError, "'user_id' is missing")
    end

    it "requires static credentials, like GitLab's 0.1.0" do
      expect { described_class.new(base_settings(client_secret: "")) }
        .to raise_error(MsGraphMailer::ConfigurationError, "'client_secret' is missing")
    end

    it "exposes the settings as ms_graph_settings for compatibility" do
      d = described_class.new(base_settings)
      expect(d.ms_graph_settings[:graph_endpoint]).to eq("https://graph.microsoft.com")
      expect(d.ms_graph_settings[:azure_ad_endpoint]).to eq("https://login.microsoftonline.com")
    end

    describe "credentials source" do
      def credentials_of(delivery)
        delivery.send(:credentials)
      end

      let(:aws_only) { { user_id: "notifications@example.com", aws_secret_id: "shared/entra-mailer/test", aws_region: "us-east-1" } }

      it "uses tenant/client_id/client_secret from the settings when given" do
        expect(credentials_of(described_class.new(base_settings))).to be_a(MsGraphMailer::Credentials::Static)
      end

      it "uses AWS Secrets Manager when only aws_secret_id is given" do
        credentials = credentials_of(described_class.new(aws_only))
        expect(credentials).to be_a(MsGraphMailer::Credentials::AwsSecretsManager)
        expect(credentials.secret_id).to eq("shared/entra-mailer/test")
      end

      it "passes AWS access keys to the AWS Secrets Manager source" do
        credentials = credentials_of(described_class.new(aws_only.merge(aws_access_key_id: "AKIAEXAMPLE0001",
                                                                        aws_secret_access_key: "example-secret-key")))
        expect(credentials.aws_credentials_source).to eq("access_keys")
        expect(credentials_of(described_class.new(aws_only)).aws_credentials_source).to eq("default_chain")
      end

      it "rejects both sources unless credentials_provider picks one" do
        expect { described_class.new(base_settings(aws_secret_id: "shared/entra-mailer/test")) }
          .to raise_error(MsGraphMailer::ConfigurationError, /Both tenant\/client_id\/client_secret and aws_secret_id/)
      end

      it "honours an explicit credentials_provider when both are given" do
        both = base_settings(aws_secret_id: "shared/entra-mailer/test")
        expect(credentials_of(described_class.new(both.merge(credentials_provider: :static))))
          .to be_a(MsGraphMailer::Credentials::Static)
        expect(credentials_of(described_class.new(both.merge(credentials_provider: "aws_secrets_manager"))))
          .to be_a(MsGraphMailer::Credentials::AwsSecretsManager)
      end

      it "explains both options when no credentials are given" do
        expect { described_class.new(user_id: "notifications@example.com") }
          .to raise_error(MsGraphMailer::ConfigurationError, /set tenant, client_id and client_secret, or aws_secret_id/)
      end
    end

    it "rejects an unknown credentials provider" do
      expect { described_class.new(base_settings(credentials_provider: :vault)) }
        .to raise_error(MsGraphMailer::ConfigurationError, /Unknown credentials_provider/)
    end
  end

  describe "save_to_sent_items: true (MIME, same as GitLab's 0.1.0)" do
    it "posts the base64 MIME message, keeping Bcc in the headers" do
      stub_token
      send_mail = stub_send_mail
      delivery(save_to_sent_items: true).deliver!(build_mail(bcc: "hidden@example.org"))

      expect(send_mail).to have_been_requested.once
      expect(WebMock).to(have_requested(:post, GraphStubs::SEND_MAIL_URL).with do |request|
        mime = sent_mime(request)
        request.headers["Content-Type"] == "text/plain" &&
          request.headers["Authorization"] == "Bearer token-1" &&
          mime.include?("Bcc: hidden@example.org") &&
          mime.include?("Subject: Hello")
      end)
    end
  end

  describe "save_to_sent_items: false (JSON)" do
    it "posts JSON with saveToSentItems false and all recipients" do
      stub_token
      stub_send_mail
      mail = build_mail(cc: "jane@example.com", bcc: "hidden@example.org", reply_to: "jane@example.com")
      delivery(save_to_sent_items: false).deliver!(mail)

      expect(WebMock).to(have_requested(:post, GraphStubs::SEND_MAIL_URL).with do |request|
        json = sent_json(request)
        message = json["message"]
        request.headers["Content-Type"] == "application/json" &&
          json["saveToSentItems"] == false &&
          message["subject"] == "Hello" &&
          message["body"] == { "contentType" => "HTML", "content" => "<p>Hi</p>" } &&
          message["toRecipients"] == [ { "emailAddress" => { "address" => "patient@example.org" } } ] &&
          message["ccRecipients"] == [ { "emailAddress" => { "address" => "jane@example.com" } } ] &&
          message["bccRecipients"] == [ { "emailAddress" => { "address" => "hidden@example.org" } } ] &&
          message["replyTo"] == [ { "emailAddress" => { "address" => "jane@example.com" } } ] &&
          message["from"] == { "emailAddress" => { "address" => "notifications@example.com", "name" => "App" } }
      end)
    end

    it "sends to the user_id mailbox URL" do
      stub_token
      stub_send_mail
      delivery(save_to_sent_items: false).deliver!(build_mail)
      expect(WebMock).to have_requested(:post, "https://graph.microsoft.com/v1.0/users/notifications@example.com/sendMail")
    end

    it "rejects requests over Graph's size limit before sending" do
      stub_token
      send_mail = stub_send_mail
      mail = build_mail
      mail.attachments["big.bin"] = "x" * 3_100_000

      expect { delivery(save_to_sent_items: false).deliver!(mail) }
        .to raise_error(MsGraphMailer::DeliveryError, /Graph accepts up to/)
      expect(send_mail).not_to have_been_requested
    end
  end

  describe "tokens" do
    it "reuses a cached token across deliveries" do
      token = stub_token
      stub_send_mail
      2.times { delivery.deliver!(build_mail) }
      expect(token).to have_been_requested.once
    end

    it "requests the token for the tenant with the Graph .default scope" do
      stub_token
      stub_send_mail
      delivery.deliver!(build_mail)
      expect(WebMock).to(have_requested(:post, "https://login.microsoftonline.com/tenant-id/oauth2/v2.0/token")
        .with(body: hash_including("grant_type" => "client_credentials", "client_id" => "client-id",
                                   "scope" => "https://graph.microsoft.com/.default")))
    end

    it "gets a new token once when Graph returns 401" do
      token = stub_request(:post, GraphStubs::TOKEN_URL)
              .to_return({ status: 200, body: { access_token: "old", expires_in: 3600 }.to_json },
                         { status: 200, body: { access_token: "new", expires_in: 3600 }.to_json })
      stub_request(:post, GraphStubs::SEND_MAIL_URL)
        .with(headers: { "Authorization" => "Bearer old" }).to_return(status: 401, body: graph_error("InvalidAuthenticationToken"))
      ok = stub_request(:post, GraphStubs::SEND_MAIL_URL)
           .with(headers: { "Authorization" => "Bearer new" }).to_return(status: 202)

      delivery.deliver!(build_mail)
      expect(token).to have_been_requested.twice
      expect(ok).to have_been_requested.once
    end
  end

  describe "credential rotation" do
    let(:provider) do
      Class.new do
        attr_reader :refreshes

        def initialize
          @refreshes = 0
          @value = { tenant: "tenant-id", client_id: "client-id", client_secret: "old-secret" }
        end

        def current
          @value
        end

        def refresh!
          @refreshes += 1
          @value = @value.merge(client_secret: "new-secret")
        end
      end.new
    end

    it "reloads the credentials and retries once when Entra returns invalid_client" do
      stub_request(:post, GraphStubs::TOKEN_URL).with(body: hash_including("client_secret" => "old-secret"))
                                                .to_return(status: 401, body: { error: "invalid_client" }.to_json)
      stub_request(:post, GraphStubs::TOKEN_URL).with(body: hash_including("client_secret" => "new-secret"))
                                                .to_return(status: 200, body: { access_token: "t", expires_in: 3600 }.to_json)
      send_mail = stub_send_mail

      delivery(credentials_provider: provider).deliver!(build_mail)
      expect(provider.refreshes).to eq(1)
      expect(send_mail).to have_been_requested.once
    end

    it "raises when the reloaded credentials are also rejected" do
      stub_request(:post, GraphStubs::TOKEN_URL).to_return(status: 401, body: { error: "invalid_client" }.to_json)
      expect { delivery(credentials_provider: provider).deliver!(build_mail) }
        .to raise_error(MsGraphMailer::DeliveryError) { |e| expect(e.code).to eq("invalid_client") }
      expect(provider.refreshes).to eq(1)
    end
  end

  describe "retries" do
    it "retries throttling, honouring Retry-After up to max_retry_sleep" do
      stub_token
      stub_request(:post, GraphStubs::SEND_MAIL_URL)
        .to_return({ status: 429, headers: { "Retry-After" => "30" }, body: graph_error("TooManyRequests") },
                   { status: 202 })
      d = delivery(max_retry_sleep: 2)
      d.deliver!(build_mail)
      expect(d).to have_received(:pause).with(2).once
    end

    it "raises TransientError after max_transient_retries" do
      stub_token
      send_mail = stub_send_mail(status: 503, body: graph_error("ServiceUnavailable"))
      expect { delivery(max_transient_retries: 2).deliver!(build_mail) }
        .to raise_error(MsGraphMailer::TransientError) { |e| expect(e.status).to eq(503) }
      expect(send_mail).to have_been_requested.times(3)
    end

    it "retries a connection that never opened" do
      stub_token
      stub_request(:post, GraphStubs::SEND_MAIL_URL).to_raise(Net::OpenTimeout).then.to_return(status: 202)
      expect { delivery.deliver!(build_mail) }.not_to raise_error
    end

    it "does not retry a read timeout, to avoid duplicate messages" do
      stub_token
      send_mail = stub_request(:post, GraphStubs::SEND_MAIL_URL).to_raise(Net::ReadTimeout)
      expect { delivery.deliver!(build_mail) }.to raise_error(MsGraphMailer::DeliveryError, /Timed out/)
      expect(send_mail).to have_been_requested.once
    end

    it "does not retry permanent errors" do
      stub_token
      send_mail = stub_send_mail(status: 403, body: graph_error("ErrorAccessDenied"))
      expect { delivery.deliver!(build_mail) }
        .to raise_error(MsGraphMailer::DeliveryError) { |e|
          expect(e).not_to be_a(MsGraphMailer::TransientError)
          expect(e.code).to eq("ErrorAccessDenied")
          expect(e.message).not_to include("test") # never includes response bodies
        }
      expect(send_mail).to have_been_requested.once
    end
  end

  describe "enforce_from" do
    before do
      stub_token
      stub_send_mail
    end

    def sent_message
      message = nil
      expect(WebMock).to(have_requested(:post, GraphStubs::SEND_MAIL_URL).with { |r| message = sent_json(r)["message"] })
      message
    end

    it "sends a different From as the mailbox, named '<person> via <app>', with Reply-To" do
      mail = build_mail(from: "Jane Doe <jane@example.com>")
      delivery(save_to_sent_items: false, display_name: -> { "Clinical App" }).deliver!(mail)

      expect(sent_message["from"]).to eq("emailAddress" => { "address" => "notifications@example.com",
                                                              "name" => "Jane Doe via Clinical App" })
      expect(sent_message["replyTo"]).to eq([ { "emailAddress" => { "address" => "jane@example.com" } } ])
    end

    it "keeps an existing Reply-To" do
      mail = build_mail(from: "jane@example.com", reply_to: "team@example.com")
      delivery(save_to_sent_items: false).deliver!(mail)
      expect(sent_message["replyTo"]).to eq([ { "emailAddress" => { "address" => "team@example.com" } } ])
    end

    it "fills a missing From with the mailbox and display name" do
      mail = build_mail(from: nil)
      delivery(save_to_sent_items: false, display_name: "Clinical App").deliver!(mail)
      expect(sent_message["from"]).to eq("emailAddress" => { "address" => "notifications@example.com", "name" => "Clinical App" })
    end

    it "leaves a From on the mailbox untouched (case-insensitive)" do
      mail = build_mail(from: "Jane Doe via App <Notifications@Example.com>")
      delivery(save_to_sent_items: false).deliver!(mail)
      expect(sent_message["from"]["emailAddress"]["name"]).to eq("Jane Doe via App")
      expect(sent_message).not_to have_key("replyTo")
    end

    it "is skipped when user_id is an object id rather than an address" do
      mail = build_mail(from: "jane@example.com")
      delivery(save_to_sent_items: false, user_id: "8c8a1f2e-0000-0000-0000-000000000000").deliver!(mail)
      expect(sent_message["from"]["emailAddress"]["address"]).to eq("jane@example.com")
    end

    it "can be turned off" do
      mail = build_mail(from: "jane@example.com")
      delivery(save_to_sent_items: false, enforce_from: false).deliver!(mail)
      expect(sent_message["from"]["emailAddress"]["address"]).to eq("jane@example.com")
    end
  end
end
