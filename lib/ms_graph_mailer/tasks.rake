# frozen_string_literal: true

require_relative "diagnostics"

namespace :ms_graph_mailer do
  desc "Show mail delivery configuration and verify Entra credentials and token (sends nothing)"
  task check: :environment do
    MsGraphMailer::Diagnostics.check
  end

  desc "Send a test email: rake \"ms_graph_mailer:smoke[to@example.com,Optional From Name]\""
  task :smoke, [ :to, :display_name ] => :environment do |_task, args|
    MsGraphMailer::Diagnostics.smoke(to: args[:to], display_name: args[:display_name])
  end
end
