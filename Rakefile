# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "standard/rake"

SERVER_BACKENDS = %w[mysql postgres redis]
SERVER_BACKED_SPECS = "spec/**/*{#{SERVER_BACKENDS.join(",")}}*_spec.rb"

# Everything that needs no database server: the middleware itself, the memory backend,
# the SQLite backend and the install generator. This is the bulk of the suite.
RSpec::Core::RakeTask.new("spec:standalone") do |t|
  t.rspec_opts = %(--exclude-pattern "#{SERVER_BACKED_SPECS.sub("spec/", "")}")
end

# Only the specs which need MySQL, PostgreSQL or Redis to be running.
RSpec::Core::RakeTask.new("spec:servers") do |t|
  t.pattern = SERVER_BACKED_SPECS
end

# One per server, so that CI can run each in its own job with just that one container
SERVER_BACKENDS.each do |backend|
  RSpec::Core::RakeTask.new("spec:#{backend}") do |t|
    t.pattern = "spec/**/*#{backend}*_spec.rb"
  end
end

RSpec::Core::RakeTask.new(:spec)

task default: :spec
