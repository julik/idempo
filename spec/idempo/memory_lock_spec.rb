# frozen_string_literal: true

require "spec_helper"

RSpec.describe Idempo::MemoryLock do
  it "keeps rejecting a key for as long as the request holding it is in flight" do
    lock = described_class.new

    lock.with("k") do
      expect { lock.with("k") {} }.to raise_error(Idempo::ConcurrentRequest)
      expect { lock.with("k") {} }.to raise_error(Idempo::ConcurrentRequest)
    end

    expect { |b| lock.with("k", &b) }.to yield_control
  end
end
