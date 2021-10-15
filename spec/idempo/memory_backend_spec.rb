# frozen_string_literal: true
require_relative 'shared_backend_specs'

RSpec.describe Idempo::MemoryBackend do
  let(:subject) do
    described_class.new
  end

  it_should_behave_like "a backend for Idempo"
end
