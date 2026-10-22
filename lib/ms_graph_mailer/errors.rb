# frozen_string_literal: true

module MsGraphMailer
  class Error < StandardError
  end

  class ConfigurationError < Error
  end

  # A delivery that failed and should not be retried as-is (bad request, access
  # denied, mailbox not found, message too large, ...).
  class DeliveryError < Error
    attr_reader :status, :code

    def initialize(message = nil, status: nil, code: nil)
      super(message)
      @status = status
      @code = code
    end
  end

  # Throttling, a Graph/Entra 5xx, a connection that never opened, or the
  # credentials store being unreachable: safe to retry later.
  class TransientError < DeliveryError
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil, **options)
      super(message, **options)
      @retry_after = retry_after
    end
  end
end
