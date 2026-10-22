# frozen_string_literal: true

require_relative "unit_helper"

RSpec.describe MsGraphMailer do
  before do
    described_class.configure do |config|
      config.user_id = "notifications@example.com"
      config.display_name = -> { "Clinical App" }
    end
  end

  it "has a version" do
    expect(MsGraphMailer::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  describe ".default_from" do
    it "combines the display name and the mailbox" do
      expect(described_class.default_from).to eq("Clinical App <notifications@example.com>")
    end

    it "evaluates a callable display name on every call" do
      name = "First"
      described_class.config.display_name = -> { name }
      expect(described_class.default_from).to eq("First <notifications@example.com>")
      name = "Second"
      expect(described_class.default_from).to eq("Second <notifications@example.com>")
    end

    it "returns the bare address without a display name" do
      described_class.config.display_name = nil
      expect(described_class.default_from).to eq("notifications@example.com")
    end

    it "quotes names that need it" do
      described_class.config.display_name = "Smith, Jones & Co"
      expect(described_class.default_from).to eq('"Smith, Jones & Co" <notifications@example.com>')
    end
  end

  describe ".from_on_behalf_of" do
    it "names the person and the app on the shared mailbox" do
      expect(described_class.from_on_behalf_of("Jane Doe"))
        .to eq("Jane Doe via Clinical App <notifications@example.com>")
    end

    it "falls back to the app name for a blank person" do
      expect(described_class.from_on_behalf_of(" ")).to eq("Clinical App <notifications@example.com>")
    end
  end
end
