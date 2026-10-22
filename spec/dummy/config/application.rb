# frozen_string_literal: true

require "logger"
require "rails"
require "action_mailer/railtie"
require "active_job/railtie"
require "ms_graph_mailer"

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.logger = Logger.new(nil)
    config.secret_key_base = "dummy-secret-key-base-for-tests-only"
    config.active_job.queue_adapter = :test
    config.action_mailer.delivery_job = "ActionMailer::MailDeliveryJob"
    # What a development/test environment usually sets; the gem overrides it
    # only where it is configured to.
    config.action_mailer.delivery_method = :test
  end
end
