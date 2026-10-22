# frozen_string_literal: true

require_relative "unit_helper"

RSpec.describe MsGraphMailer do
  it "has a version" do
    expect(MsGraphMailer::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  describe ".configure" do
    it "is not configured until configure is called" do
      expect(described_class.configured?).to be(false)
    end

    it "yields the configuration and marks the gem configured" do
      described_class.configure { |config| config.user_id = "notifications@example.com" }
      expect(described_class.configured?).to be(true)
      expect(described_class.config.user_id).to eq("notifications@example.com")
    end

    it "is cleared by reset!" do
      described_class.configure { |config| config.user_id = "notifications@example.com" }
      described_class.reset!
      expect(described_class.configured?).to be(false)
      expect(described_class.config.user_id).to be_nil
    end
  end

  it "does not offer SMTP or delivery-method switching" do
    config = described_class.config
    %i[delivery_method smtp_settings graph_environments set_default_from].each do |option|
      expect(config).not_to respond_to(option)
    end
  end
end
