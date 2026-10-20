# frozen_string_literal: true

require "spec_helper"
require "idempo/response_store"

RSpec.describe Idempo::ResponseStore do
  let(:subject) { described_class.new }
  let(:clock) { [100.0] }

  before do
    allow(Process).to receive(:clock_gettime).and_call_original
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { clock[0] }
  end

  def expiries
    subject.instance_variable_get(:@expiries).map(&:expire_at)
  end

  it "keeps only the expiry handles of responses which have not expired yet when pruning" do
    [5, 4, 3, 2, 1].each { |ttl| subject.save("key-#{ttl}", "response-#{ttl}", ttl) }
    expect(expiries).to eq([105.0, 104.0, 103.0, 102.0, 101.0])

    clock[0] = 103.0
    subject.prune

    expect(expiries).to eq([105.0, 104.0])
    expect(subject.lookup("key-5")).to eq("response-5")
    expect(subject.lookup("key-4")).to eq("response-4")
    expect(subject.lookup("key-2")).to be_nil
  end

  it "retains no expiry handles once every response has expired" do
    [3, 2, 1].each { |ttl| subject.save("key-#{ttl}", "response-#{ttl}", ttl) }

    clock[0] = 110.0
    subject.prune

    expect(expiries).to be_empty
  end
end
