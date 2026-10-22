# frozen_string_literal: true

require "rails/generators"

module MsGraphMailer
  module Generators
    # rails generate ms_graph_mailer:install
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)
      desc "Creates config/initializers/ms_graph_mailer.rb"

      def copy_initializer
        template "initializer.rb", "config/initializers/ms_graph_mailer.rb"
      end

      def show_next_steps
        say <<~TEXT

          Next steps:
            1. Edit config/initializers/ms_graph_mailer.rb (user_id, credentials, display_name).
            2. If ApplicationMailer sets `default from:`, remove it when set_default_from is true.
            3. Remove any other initializer that sets ActionMailer delivery_method / smtp_settings.
            4. Run: bin/rails ms_graph_mailer:check
        TEXT
      end
    end
  end
end
