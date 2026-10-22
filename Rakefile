# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

# Unit and integration specs run in separate processes: the integration specs
# boot a Rails application, which must not leak into the unit specs.
RSpec::Core::RakeTask.new("spec:unit") { |t| t.pattern = "spec/unit/**/*_spec.rb" }
RSpec::Core::RakeTask.new("spec:integration") { |t| t.pattern = "spec/integration/**/*_spec.rb" }

desc "Run unit and integration specs"
task spec: %w[spec:unit spec:integration]

task default: :spec
