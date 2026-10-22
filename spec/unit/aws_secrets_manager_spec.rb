# frozen_string_literal: true

require_relative "unit_helper"

RSpec.describe MsGraphMailer::Credentials::AwsSecretsManager do
  let(:aws) { Aws::SecretsManager::Client.new(stub_responses: true, region: "us-east-1") }
  let(:notifier) { double("notifier", call: nil) }
  let(:provider) { described_class.new(secret_id: "shared/entra-mailer/test", ttl: 600, client: aws, error_notifier: notifier) }
  let(:clock) { [ 1000.0 ] }

  def secret(client_secret, tenant_key: "tenant_id")
    { secret_string: { tenant_key => "tenant-id", "client_id" => "client-id", "client_secret" => client_secret }.to_json }
  end

  before { allow(provider).to receive(:monotonic) { clock.first } }

  it "reads tenant_id, client_id and client_secret from the JSON secret" do
    aws.stub_responses(:get_secret_value, secret("s1"))
    expect(provider.current).to eq(tenant: "tenant-id", client_id: "client-id", client_secret: "s1")
  end

  it "also accepts a 'tenant' key" do
    aws.stub_responses(:get_secret_value, secret("s1", tenant_key: "tenant"))
    expect(provider.current[:tenant]).to eq("tenant-id")
  end

  it "caches the value until the TTL expires, then re-reads it (rotation without restart)" do
    aws.stub_responses(:get_secret_value, [ secret("s1"), secret("s2") ])
    expect(provider.current[:client_secret]).to eq("s1")
    clock[0] += 599
    expect(provider.current[:client_secret]).to eq("s1")
    clock[0] += 2
    expect(provider.current[:client_secret]).to eq("s2")
  end

  it "re-reads immediately on refresh!, at most once per 30 seconds" do
    aws.stub_responses(:get_secret_value, [ secret("s1"), secret("s2"), secret("s3") ])
    provider.current
    expect(provider.refresh![:client_secret]).to eq("s2")
    clock[0] += 10
    expect(provider.refresh![:client_secret]).to eq("s2")
    clock[0] += 21
    expect(provider.refresh![:client_secret]).to eq("s3")
  end

  it "keeps the last good value when AWS fails later, and reports it" do
    aws.stub_responses(:get_secret_value, [ secret("s1"), "ServiceUnavailableException", secret("s2") ])
    provider.current
    clock[0] += 601
    expect(provider.current[:client_secret]).to eq("s1")
    expect(notifier).to have_received(:call).once
    clock[0] += 31
    expect(provider.current[:client_secret]).to eq("s2")
  end

  it "raises TransientError when AWS fails and nothing is cached" do
    aws.stub_responses(:get_secret_value, "ServiceUnavailableException")
    expect { provider.current }.to raise_error(MsGraphMailer::TransientError, /Could not read secret/)
  end

  it "raises ConfigurationError for a secret that is not JSON" do
    aws.stub_responses(:get_secret_value, { secret_string: "not json" })
    expect { provider.current }.to raise_error(MsGraphMailer::ConfigurationError, /not valid JSON/)
  end

  it "raises ConfigurationError for missing keys, without revealing values" do
    aws.stub_responses(:get_secret_value, { secret_string: { tenant_id: "t", client_id: "c" }.to_json })
    expect { provider.current }.to raise_error(MsGraphMailer::ConfigurationError, /missing client_secret/)
  end

  it "requires a secret id" do
    expect { described_class.new(secret_id: "") }.to raise_error(MsGraphMailer::ConfigurationError)
  end

  it "shares one instance per secret and region" do
    a = described_class.for(secret_id: "x", region: "us-east-1")
    expect(described_class.for(secret_id: "x", region: "us-east-1")).to equal(a)
    expect(described_class.for(secret_id: "x", region: "us-west-2")).not_to equal(a)
  end
end
