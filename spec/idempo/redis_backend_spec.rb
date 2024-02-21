# frozen_string_literal: true

require "spec_helper"
require_relative "shared_backend_specs"
require "redis"

RSpec.describe Idempo::RedisBackend do
  let(:subject) do
    require "redis"
    described_class.new
  end

  it_should_behave_like "a backend for Idempo"

  it "does not save the payload if store() is called when the lock has expired" do
    redis = Redis.new
    request = Fiber.new do
      subject.with_idempotency_key("req1") do |store|
        Fiber.yield
        store.store(data: +"From first request", ttl: 300)
      end
    end

    request.resume
    expect(redis.del("idempo:lock:req1")).to eq(1) # Should have deleted one key

    request.resume
    expect(redis.get("idempo:response:req1")).to be_nil # Save should have been canceled
  end

  it "does not save the payload if store() is called when the lock was stolen by a different caller" do
    redis = Redis.new
    request = Fiber.new do
      subject.with_idempotency_key("req2") do |store|
        redis.set("idempo:lock:req2", "Stolen by another request")
        Fiber.yield
        store.store(data: +"From first request", ttl: 300)
      end
    end

    request.resume
    expect(redis.del("idempo:lock:req2")).to eq(1) # The lock key should have been preserved and not deleted

    request.resume
    expect(redis.get("idempo:response:req2")).to be_nil # Save should have been canceled
  end

  it "uses known key naming patterns (so that tests continue working)" do
    redis = Redis.new

    expect(redis.get("idempo:lock:req3")).to be_nil

    request = Fiber.new do
      subject.with_idempotency_key("req3") do |store|
        expect(redis.get("idempo:lock:req3")).to be_kind_of(String)
        Fiber.yield
        store.store(data: +"From third request", ttl: 300)
      end
    end

    request.resume
    expect(redis.get("idempo:lock:req3")).to be_kind_of(String) # The lock is held

    request.resume
    expect(redis.get("idempo:lock:req3")).to be_nil # Lock released
    expect(redis.get("idempo:response:req3")).to eq("From third request".b) # Save should have been performed
  end
end
