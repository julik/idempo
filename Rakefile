# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "standard/rake"
require "appraisal"

RSpec::Core::RakeTask.new(:spec)
task default: :spec

if !ENV["APPRAISAL_INITIALIZED"]
  task default: :appraisal
end
