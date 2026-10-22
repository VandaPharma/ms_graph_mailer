# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../dummy/config/application"
Dummy::Application.initialize!

require "rake"
require "tmpdir"

class DummyMailer < ActionMailer::Base
  # The application sets its own default From on the user_id mailbox.
  default from: "Dummy App <notifications@example.com>"

  def notice(to)
    mail(to: to, subject: "Notice", content_type: "text/html", body: "<p>Notice</p>")
  end

  # The shared-mailbox pattern: sent from the app mailbox under the person's
  # name, the person copied and receiving replies.
  def on_behalf_of(to, person_name, person_email)
    mail(
      to: to,
      from: email_address_with_name("notifications@example.com", "#{person_name} via Dummy App"),
      cc: person_email,
      reply_to: person_email,
      subject: "From a person",
      content_type: "text/html",
      body: "<p>Hello</p>"
    )
  end
end

# Configured through ActionMailer settings only, without MsGraphMailer.configure.
class LegacyMailer < ActionMailer::Base
  self.delivery_method = :ms_graph
  self.ms_graph_settings = {
    user_id: "legacy@example.com", tenant: "tenant-id", client_id: "client-id", client_secret: "client-secret"
  }

  def notice(to)
    mail(from: "legacy@example.com", to: to, subject: "Legacy", content_type: "text/html", body: "<p>Legacy</p>")
  end
end

RSpec.describe "Rails integration" do
  before do
    MsGraphMailer::AccessToken.reset!
    queue_adapter.enqueued_jobs.clear
    stub_token
  end

  def queue_adapter
    ActiveJob::Base.queue_adapter
  end

  # Runs the jobs enqueued so far (works the same on Rails 6.1 and 8.1).
  def run_enqueued_jobs
    jobs = queue_adapter.enqueued_jobs.dup
    queue_adapter.enqueued_jobs.clear
    jobs.each { |job| job[:job].new(*ActiveJob::Arguments.deserialize(job[:args])).perform_now }
  end

  def sent_message
    message = nil
    expect(WebMock).to(have_requested(:post, GraphStubs::SEND_MAIL_URL).with { |r| message = sent_json(r) })
    message
  end

  it "selects the Graph delivery method when configure is called" do
    expect(ActionMailer::Base.delivery_method).to eq(:ms_graph)
    expect(ActionMailer::Base.ms_graph_settings).to include(user_id: "notifications@example.com",
                                                                         save_to_sent_items: false)
  end

  it "works with plain ActionMailer settings, without configure (MIME send)" do
    stub_send_mail
    LegacyMailer.notice("patient@example.org").deliver_now
    expect(WebMock).to(have_requested(:post, "https://graph.microsoft.com/v1.0/users/legacy@example.com/sendMail").with do |request|
      request.headers["Content-Type"] == "text/plain" && sent_mime(request).include?("Subject: Legacy")
    end)
  end

  it "leaves ActionMailer alone when configure was never called" do
    state = %i[@config @configured].to_h { |ivar| [ ivar, MsGraphMailer.instance_variable_get(ivar) ] }
    MsGraphMailer.instance_variable_set(:@config, nil)
    MsGraphMailer.instance_variable_set(:@configured, false)
    expect(MsGraphMailer.configured?).to be(false)
    expect(ActionMailer::Base.delivery_methods).to have_key(:ms_graph)
  ensure
    state.each { |ivar, value| MsGraphMailer.instance_variable_set(ivar, value) }
  end

  it "does not change the application's default From" do
    expect(ActionMailer::Base.default[:from]).to be_nil
  end

  it "sends a From on another address as the mailbox, '<person> via <display_name>', with Reply-To" do
    stub_send_mail
    DummyMailer.notice("patient@example.org").tap { |m| m.from = "Jane Doe <jane@example.com>" }.deliver_now

    message = sent_message["message"]
    expect(message["from"]).to eq("emailAddress" => { "address" => "notifications@example.com", "name" => "Jane Doe via Dummy App" })
    expect(message["replyTo"]).to eq([ { "emailAddress" => { "address" => "jane@example.com" } } ])
  end

  it "delivers with deliver_now, without a Sent Items copy" do
    stub_send_mail
    DummyMailer.notice("patient@example.org").deliver_now

    json = sent_message
    expect(json["saveToSentItems"]).to eq(false)
    expect(json["message"]["from"]).to eq("emailAddress" => { "address" => "notifications@example.com", "name" => "Dummy App" })
  end

  it "delivers with deliver_later" do
    stub_send_mail
    DummyMailer.notice("patient@example.org").deliver_later
    expect(queue_adapter.enqueued_jobs.map { |job| job[:job] }).to eq([ ActionMailer::MailDeliveryJob ])
    run_enqueued_jobs
    expect(sent_message["message"]["toRecipients"]).to eq([ { "emailAddress" => { "address" => "patient@example.org" } } ])
  end

  it "sends on behalf of a person from the shared mailbox with Cc and Reply-To" do
    stub_send_mail
    DummyMailer.on_behalf_of("patient@example.org", "Jane Doe", "jane@example.com").deliver_now

    message = sent_message["message"]
    expect(message["from"]).to eq("emailAddress" => { "address" => "notifications@example.com", "name" => "Jane Doe via Dummy App" })
    expect(message["ccRecipients"]).to eq([ { "emailAddress" => { "address" => "jane@example.com" } } ])
    expect(message["replyTo"]).to eq([ { "emailAddress" => { "address" => "jane@example.com" } } ])
    expect(message).not_to have_key("bccRecipients")
  end

  it "retries deliver_later jobs on transient errors" do
    handlers = ActionMailer::MailDeliveryJob.rescue_handlers.map(&:first)
    expect(handlers).to include("MsGraphMailer::TransientError")

    stub_send_mail(status: 503, body: graph_error("ServiceUnavailable"))
    allow_any_instance_of(MsGraphMailer::Delivery).to receive(:pause)
    DummyMailer.notice("patient@example.org").deliver_later
    expect { run_enqueued_jobs }.not_to raise_error
    retried = queue_adapter.enqueued_jobs
    expect(retried.map { |job| job[:job] }).to eq([ ActionMailer::MailDeliveryJob ])
    expect(retried.first[:at]).to be > Time.now.to_f
  end

  it "rejects an invalid configuration at boot" do
    config = MsGraphMailer.config
    config.user_id = nil
    expect { MsGraphMailer.apply!(Class.new(ActionMailer::Base)) }
      .to raise_error(MsGraphMailer::ConfigurationError, /user_id/)
  ensure
    config.user_id = "notifications@example.com"
  end

  it "provides the rake tasks" do
    Rails.application.load_tasks
    expect(Rake::Task.task_defined?("ms_graph_mailer:check")).to be(true)
    expect(Rake::Task.task_defined?("ms_graph_mailer:smoke")).to be(true)
  end

  it "checks configuration and credentials without sending" do
    send_mail = stub_send_mail
    out = StringIO.new
    MsGraphMailer::Diagnostics.check(out: out)
    expect(out.string).to include("delivery_method:      ms_graph", "credentials_provider: static (auto)", "token:                OK")
    expect(out.string).not_to include("client-secret")
    expect(send_mail).not_to have_been_requested
  end

  it "sends a smoke test with the default From" do
    stub_send_mail
    MsGraphMailer::Diagnostics.smoke(to: "me@example.com", out: StringIO.new)
    expect(sent_message["message"]["from"]["emailAddress"]).to eq("address" => "notifications@example.com", "name" => "Dummy App")
  end

  it "sends a smoke test with a custom From name (step 0 check)" do
    stub_send_mail
    MsGraphMailer::Diagnostics.smoke(to: "me@example.com", display_name: "Jane Doe via Dummy App",
                                                 out: StringIO.new)
    expect(sent_message["message"]["from"]["emailAddress"]["name"]).to eq("Jane Doe via Dummy App")
  end

  it "provides the install generator" do
    require "generators/ms_graph_mailer/install/install_generator"
    Dir.mktmpdir do |dir|
      MsGraphMailer::Generators::InstallGenerator.start([ "--quiet" ], destination_root: dir)
      initializer = File.read(File.join(dir, "config/initializers/ms_graph_mailer.rb"))
      expect(initializer).to include("config.save_to_sent_items", "config.credentials_provider", 'config.display_name = -> { "Dummy" }')
    end
  end
end
