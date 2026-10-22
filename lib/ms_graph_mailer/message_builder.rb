# frozen_string_literal: true

module MsGraphMailer
  # Converts a Mail::Message into a Graph `message` resource for JSON sendMail.
  # Graph takes a single body, so the HTML part is used when there is one.
  #
  # https://learn.microsoft.com/graph/api/resources/message
  class MessageBuilder
    def initialize(message)
      @message = message
    end

    def to_graph
      {
        subject: @message.subject.to_s,
        body: body,
        from: first_recipient(:from),
        toRecipients: recipients(:to),
        ccRecipients: recipients(:cc),
        bccRecipients: recipients(:bcc),
        replyTo: recipients(:reply_to),
        attachments: attachments
      }.reject { |_, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
    end

    private

    def body
      part = @message.multipart? ? (@message.html_part || @message.text_part) : @message
      return { contentType: "Text", content: "" } if part.nil?

      { contentType: part.mime_type == "text/html" ? "HTML" : "Text", content: part.decoded.to_s }
    end

    def first_recipient(field)
      recipients(field).first
    end

    def recipients(field)
      header = @message[field]
      return [] if header.nil?

      Array(header.addrs).map do |address|
        email = { address: address.address }
        email[:name] = address.display_name unless address.display_name.to_s.empty?
        { emailAddress: email }
      end
    end

    def attachments
      @message.attachments.map do |attachment|
        # Mail assigns a Content-ID lazily (e.g. when a view calls #url); inline
        # images need one for their cid: references.
        attachment.add_content_id if attachment.inline? && !attachment.has_content_id?
        graph_attachment = {
          "@odata.type": "#microsoft.graph.fileAttachment",
          name: attachment.filename.to_s,
          contentType: attachment.mime_type.to_s,
          contentBytes: [ attachment.decoded ].pack("m0"),
          isInline: attachment.inline?
        }
        content_id = attachment.content_id.to_s.delete("<>")
        graph_attachment[:contentId] = content_id unless content_id.empty?
        graph_attachment
      end
    end
  end
end
