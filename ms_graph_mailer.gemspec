# frozen_string_literal: true

require_relative "lib/ms_graph_mailer/version"

# Installed from GitHub:
#   gem "ms_graph_mailer", github: "VandaPharma/ms_graph_mailer", tag: "v1.0.0"
Gem::Specification.new do |spec|
  spec.name = "ms_graph_mailer"
  spec.version = MsGraphMailer::VERSION
  spec.authors = [ "Vanda Pharmaceuticals Inc." ]
  spec.license = "MIT"

  spec.summary = "ActionMailer delivery through Microsoft Graph sendMail, with optional Sent Items copy " \
                 "and Entra credentials from AWS Secrets Manager"
  spec.description = "Based on GitLab's microsoft_graph_mailer 0.1.0, with the same settings. Adds a " \
                     "saveToSentItems setting, credentials from AWS Secrets Manager with rotation without " \
                     "restart, token caching, timeouts and retries, an SMTP fallback switch, a shared-mailbox " \
                     "From policy and Rails integration."
  spec.homepage = "https://github.com/VandaPharma/ms_graph_mailer"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "documentation_uri" => "#{spec.homepage}/blob/main/README.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    # Distributed from GitHub; blocks an accidental `gem push` / `rake release` to rubygems.org.
    "allowed_push_host" => "https://rubygems.pkg.github.com/VandaPharma"
  }

  spec.files = Dir["lib/**/*", "docs/**/*", "LICENSE.txt", "README.md", "CHANGELOG.md", "SECURITY.md"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "actionmailer", ">= 6.1", "< 9"
  spec.add_dependency "mail", ">= 2.8", "< 3"
  spec.add_dependency "railties", ">= 6.1", "< 9"
  # aws-sdk-secretsmanager is optional: add it to the application's Gemfile when
  # using credentials_provider :aws_secrets_manager.
end
