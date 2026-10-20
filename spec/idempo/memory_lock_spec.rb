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

  it "does not let a third request in while the first one is running on another thread" do
    lock = described_class.new
    a_entered = Queue.new
    a_may_finish = Queue.new

    request_a = Thread.new do
      lock.with("k") do
        a_entered << true
        a_may_finish.pop
      end
    end

    begin
      a_entered.pop
      expect { lock.with("k") {} }.to raise_error(Idempo::ConcurrentRequest)

      # C runs on its own thread so that it is a separate request, not a nested call inside A
      request_c = Thread.new { lock.with("k") { :ran_concurrently_with_a } }
      expect { request_c.value }.to raise_error(Idempo::ConcurrentRequest)
    ensure
      a_may_finish << true
      request_a.join
    end
  end
end
