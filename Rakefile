# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "standard/rake"

SERVER_BACKED_SPECS = "spec/**/*{mysql,postgres,redis}*_spec.rb"

# Everything that needs no database server: the middleware itself, the memory backend,
# the SQLite backend and the install generator. This is the bulk of the suite.
RSpec::Core::RakeTask.new("spec:standalone") do |t|
  t.rspec_opts = %(--exclude-pattern "#{SERVER_BACKED_SPECS.sub("spec/", "")}")
end

# Only the specs which need MySQL, PostgreSQL or Redis to be running.
RSpec::Core::RakeTask.new("spec:servers") do |t|
  t.pattern = SERVER_BACKED_SPECS
end

RSpec::Core::RakeTask.new(:spec)

task default: :spec
