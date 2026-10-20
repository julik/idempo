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
    expect(subject.instance_variable_get(:@values).keys).to contain_exactly("key-5", "key-4")
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

  it "agrees with a naive reference model under random sequences of operations" do
    rng = Random.new(RSpec.configuration.seed)

    200.times do |round|
      store = described_class.new
      model = {}
      ops = []
      clock[0] = 100.0

      check = lambda do |what, actual, expected|
        next if actual == expected
        raise "#{what}: expected #{expected.inspect}, got #{actual.inspect} " \
          "(--seed #{RSpec.configuration.seed}, round #{round}, ops #{ops.inspect})"
      end

      60.times do
        # Whole-second TTLs and clock steps so that prunes land exactly on expire_at often
        case rng.rand(4)
        when 0
          key, ttl = "k#{rng.rand(6)}", rng.rand(1..5)
          ops << [:save, key, ttl, clock[0]]
          store.save(key, "v#{ops.length}", ttl)
          model[key] = ["v#{ops.length}", clock[0] + ttl]
        when 1
          key = "k#{rng.rand(6)}"
          ops << [:lookup, key, clock[0]]
          payload, expire_at = model[key]
          check.call("lookup(#{key})", store.lookup(key), (payload if expire_at && expire_at > clock[0]))
        when 2
          ops << [:prune, clock[0]]
          store.prune
        when 3
          clock[0] += rng.rand(0..2)
          next
        end

        now = clock[0]
        handles = store.instance_variable_get(:@expiries)
        values = store.instance_variable_get(:@values)
        at = handles.map(&:expire_at)
        check.call("expiries sorted descending", at, at.sort.reverse)
        check.call("expired handles", at.select { |t| t <= now }, [])
        check.call("expired values", values.values.select { |v| v.expire_at <= now }.map(&:key), [])
        unreachable = values.values.reject { |v| handles.any? { |h| h.key == v.key && h.expire_at == v.expire_at } }
        check.call("values without an expiry handle", unreachable.map(&:key), [])
      end

      clock[0] += 10
      store.prune
      check.call("handles after everything expired", store.instance_variable_get(:@expiries), [])
      check.call("values after everything expired", store.instance_variable_get(:@values), {})
    end
  end
end
