# frozen_string_literal: true

require_relative "unit_helper"

RSpec.describe MsGraphMailer::MessageBuilder do
  def graph(mail)
    described_class.new(mail).to_graph
  end

  it "prefers the HTML part of a multipart message" do
    message = graph(build_mail(text: true, html: "<b>rich</b>"))
    expect(message[:body]).to eq(contentType: "HTML", content: "<b>rich</b>")
  end

  it "uses a plain-text body" do
    mail = Mail.new(from: "a@example.com", to: "b@example.com", subject: "s", body: "plain")
    expect(graph(mail)[:body]).to eq(contentType: "Text", content: "plain")
  end

  it "keeps UTF-8 subjects, bodies and display names" do
    mail = build_mail(from: "Zoë Müller <notifications@example.com>", subject: "Grüße ✓", html: "<p>Привет</p>")
    message = graph(mail)
    expect(message[:subject]).to eq("Grüße ✓")
    expect(message[:body][:content]).to eq("<p>Привет</p>")
    expect(message[:from]).to eq(emailAddress: { address: "notifications@example.com", name: "Zoë Müller" })
  end

  it "maps several recipients with display names" do
    mail = build_mail(to: [ "A <a@example.org>", "b@example.org" ])
    expect(graph(mail)[:toRecipients]).to eq([
      { emailAddress: { address: "a@example.org", name: "A" } },
      { emailAddress: { address: "b@example.org" } }
    ])
  end

  it "omits empty recipient lists" do
    message = graph(build_mail)
    expect(message.keys).not_to include(:ccRecipients, :bccRecipients, :replyTo, :attachments)
  end

  it "encodes file and inline attachments" do
    mail = build_mail
    mail.attachments["report.pdf"] = { mime_type: "application/pdf", content: "%PDF-1.4" }
    mail.attachments.inline["logo.png"] = { mime_type: "image/png", content: "PNG" }
    attachments = graph(mail)[:attachments]

    pdf = attachments.find { |a| a[:name] == "report.pdf" }
    logo = attachments.find { |a| a[:name] == "logo.png" }
    expect(pdf).to include("@odata.type": "#microsoft.graph.fileAttachment", contentType: "application/pdf",
                           contentBytes: [ "%PDF-1.4" ].pack("m0"), isInline: false)
    expect(logo).to include(isInline: true, contentType: "image/png")
    expect(logo[:contentId]).not_to be_empty
    expect(logo[:contentId]).not_to include("<")
  end

  it "keeps the Content-ID an HTML view referenced via #url" do
    mail = build_mail
    mail.attachments.inline["logo.png"] = { mime_type: "image/png", content: "PNG" }
    cid = mail.attachments["logo.png"].url.delete_prefix("cid:")
    expect(graph(mail)[:attachments].first[:contentId]).to eq(cid)
  end
end
