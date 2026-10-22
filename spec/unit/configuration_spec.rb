# frozen_string_literal: true

require_relative "unit_helper"

RSpec.describe MsGraphMailer::Configuration do
  subject(:config) { described_class.new }

  describe "#validate!" do
    it "requires user_id for Graph" do
      expect { config.validate! }.to raise_error(MsGraphMailer::ConfigurationError, /user_id/)
    end

    it "requires static credentials" do
      config.user_id = "notifications@example.com"
      config.tenant = "t"
      expect { config.validate! }
        .to raise_error(MsGraphMailer::ConfigurationError, /client_id, client_secret/)
    end

    it "requires aws_secret_id for the AWS provider" do
      config.user_id = "notifications@example.com"
      config.credentials_provider = :aws_secrets_manager
      expect { config.validate! }.to raise_error(MsGraphMailer::ConfigurationError, /aws_secret_id/)
    end

    it "accepts credentials from the initializer without naming a provider" do
      config.user_id = "notifications@example.com"
      config.tenant = "t"
      config.client_id = "c"
      config.client_secret = "s"
      expect { config.validate! }.not_to raise_error
      expect(config.resolved_credentials_provider).to eq("static")
    end

    it "accepts an AWS secret without naming a provider" do
      config.user_id = "notifications@example.com"
      config.aws_secret_id = "shared/entra-mailer/production"
      expect { config.validate! }.not_to raise_error
      expect(config.resolved_credentials_provider).to eq("aws_secrets_manager")
    end

    it "rejects both credential sources unless credentials_provider picks one" do
      config.user_id = "notifications@example.com"
      config.tenant = "t"
      config.client_id = "c"
      config.client_secret = "s"
      config.aws_secret_id = "shared/entra-mailer/production"
      expect { config.validate! }.to raise_error(MsGraphMailer::ConfigurationError, /Both/)

      config.credentials_provider = :aws_secrets_manager
      expect { config.validate! }.not_to raise_error
      expect(config.resolved_credentials_provider).to eq("aws_secrets_manager")
    end

    it "requires one credential source" do
      config.user_id = "notifications@example.com"
      expect { config.validate! }
        .to raise_error(MsGraphMailer::ConfigurationError, /tenant, client_id and client_secret, or aws_secret_id/)
    end

    it "rejects an unknown credentials_provider" do
      config.user_id = "notifications@example.com"
      config.credentials_provider = :vault
      expect { config.validate! }.to raise_error(MsGraphMailer::ConfigurationError, /must be one of auto, static, aws_secrets_manager/)
    end

  end

  it "builds Delivery settings with save_to_sent_items" do
    config.save_to_sent_items = false
    expect(config.delivery_settings).to include(save_to_sent_items: false,
                                                graph_endpoint: "https://graph.microsoft.com")
  end
end
