# frozen_string_literal: true

require 'spec_helper'
require_relative 'shared_backend_specs'

RSpec.describe Idempo::RedisBackend do
  let(:subject) do
    require 'redis'
    described_class.new(Redis.new)
  end

  it_should_behave_like "a backend for Idempo"
end
