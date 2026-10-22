# frozen_string_literal: true

require_relative "unit_helper"

RSpec.describe MsGraphMailer::Configuration do
  subject(:config) { described_class.new }

  describe "#resolved_delivery_method" do
    it "uses Microsoft Graph in graph_environments when delivery_method is unset" do
      config.delivery_method = nil
      config.graph_environments = %w[staging production]
      expect(config.resolved_delivery_method("production")).to eq("microsoft_graph")
      expect(config.resolved_delivery_method("development")).to be_nil
    end

    it "honours an explicit value in any environment, case-insensitively" do
      config.delivery_method = " SMTP "
      expect(config.resolved_delivery_method("production")).to eq("smtp")
      config.delivery_method = "microsoft_graph"
      expect(config.resolved_delivery_method("development")).to eq("microsoft_graph")
    end

    it "defaults delivery_method to MAIL_DELIVERY_METHOD" do
      original = ENV["MAIL_DELIVERY_METHOD"]
      ENV["MAIL_DELIVERY_METHOD"] = "smtp"
      expect(described_class.new.delivery_method).to eq("smtp")
    ensure
      ENV["MAIL_DELIVERY_METHOD"] = original
    end
  end

  describe "#validate!" do
    before { config.graph_environments = %w[production] }

    it "rejects an unknown delivery method" do
      config.delivery_method = "sendgrid"
      expect { config.validate!("production") }.to raise_error(MsGraphMailer::ConfigurationError, /must be one of/)
    end

    it "requires smtp_settings for smtp" do
      config.delivery_method = "smtp"
      expect { config.validate!("production") }.to raise_error(MsGraphMailer::ConfigurationError, /smtp_settings/)
    end

    it "requires user_id for Graph" do
      expect { config.validate!("production") }.to raise_error(MsGraphMailer::ConfigurationError, /user_id/)
    end

    it "requires static credentials" do
      config.user_id = "notifications@example.com"
      config.tenant = "t"
      expect { config.validate!("production") }
        .to raise_error(MsGraphMailer::ConfigurationError, /client_id, client_secret/)
    end

    it "requires aws_secret_id for the AWS provider" do
      config.user_id = "notifications@example.com"
      config.credentials_provider = :aws_secrets_manager
      expect { config.validate!("production") }.to raise_error(MsGraphMailer::ConfigurationError, /aws_secret_id/)
    end

    it "skips validation when the environment keeps its own delivery method" do
      expect { config.validate!("development") }.not_to raise_error
    end
  end

  it "builds Delivery settings with save_to_sent_items" do
    config.save_to_sent_items = false
    expect(config.delivery_settings).to include(save_to_sent_items: false,
                                                graph_endpoint: "https://graph.microsoft.com")
  end
end
