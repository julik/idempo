# frozen_string_literal: true

require "active_record"
require "sqlite3"
require "tmpdir"
require "spec_helper"
require_relative "shared_backend_specs"

RSpec.describe Idempo::ActiveRecordBackend do
  let(:db_path) { File.join(Dir.tmpdir, "idempo_tests_%s.sqlite3" % Random.new(RSpec.configuration.seed).hex(4)) }

  before :each do
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: db_path, timeout: 5000)
    # WAL is what makes readers not block the single writer - Idempo needs concurrent
    # reads of stored responses while another request is taking the lock
    ActiveRecord::Base.connection.execute("PRAGMA journal_mode=WAL")
    ActiveRecord::Schema.verbose = false
    ActiveRecord::Schema.define(version: 1) do |via_definer|
      Idempo::ActiveRecordBackend.create_responses_table(via_definer)
      Idempo::ActiveRecordBackend.create_locks_table(via_definer)
    end
  end

  after :each do
    ActiveRecord::Base.connection_handler.clear_all_connections!
    Dir.glob("#{db_path}*").each { |f| File.unlink(f) }
  end

  let(:subject) { described_class.new }

  it_should_behave_like "a backend for Idempo"

  describe "the TokenLock" do
    let(:lock_key) { "some-request-fingerprint" }
    let(:connection) { ActiveRecord::Base.connection }

    it "is exclusive - a second holder cannot acquire while the first one holds it" do
      first = described_class::TokenLock.new
      second = described_class::TokenLock.new

      expect(first.acquire(connection, lock_key)).to eq(true)
      expect(second.acquire(connection, lock_key)).to eq(false)

      first.release(connection, lock_key)
      expect(second.acquire(connection, lock_key)).to eq(true)
    end

    it "does not release a lock which has been taken over by somebody else" do
      first = described_class::TokenLock.new(ttl_seconds: -1) # Already expired on acquisition
      second = described_class::TokenLock.new

      expect(first.acquire(connection, lock_key)).to eq(true)
      expect(second.acquire(connection, lock_key)).to eq(true) # Steals the expired lease

      first.release(connection, lock_key)
      expect(second.held?(connection, lock_key)).to eq(true)
    end

    it "reports the lock as not held once the lease has expired" do
      lock = described_class::TokenLock.new(ttl_seconds: 1)
      expect(lock.acquire(connection, lock_key)).to eq(true)
      expect(lock.held?(connection, lock_key)).to eq(true)
      sleep 2
      expect(lock.held?(connection, lock_key)).to eq(false)
    end

    it "raises ConcurrentRequest when the lock is held by another process" do
      squatter = described_class::TokenLock.new
      squatter.acquire(connection, lock_key)

      expect {
        subject.with_idempotency_key(lock_key) { |store| store.lookup }
      }.to raise_error(Idempo::ConcurrentRequest)

      squatter.release(connection, lock_key)
      expect { subject.with_idempotency_key(lock_key) { |store| store.lookup } }.not_to raise_error
    end

    it "does not store a response if the lease was lost while the request was running" do
      value = Random.new(RSpec.configuration.seed).bytes(128)
      backend = described_class.new(lock: described_class::TokenLock.new(ttl_seconds: 1))

      backend.with_idempotency_key(lock_key) do |store|
        sleep 2 # Our lease expires while "the application is generating the response"
        store.store(data: value, ttl: 300)
        expect(store.lookup).to be_nil
      end
    end

    it "does store a response while the lease is still held" do
      value = Random.new(RSpec.configuration.seed).bytes(128)
      backend = described_class.new(lock: described_class::TokenLock.new(ttl_seconds: 300))

      backend.with_idempotency_key(lock_key) do |store|
        store.store(data: value, ttl: 300)
        expect(store.lookup).to eq(value)
      end
    end
  end

  # An existing installation upgrades the gem before it gets around to running the new
  # migration. Its cron still calls prune!, and that must not start raising.
  it "prunes without raising when the locks table has not been created yet" do
    ActiveRecord::Base.connection.drop_table("idempo_locks")

    expect { subject.prune! }.not_to raise_error
  end

  # MySQL and PostgreSQL use connection-bound advisory locks, which cannot be lost while
  # we hold them and therefore do not implement `held?`. This covers that branch of Store.
  it "stores without a lock check when the lock implementation cannot expire" do
    non_expiring_lock = Class.new do
      def acquire(connection, key)
        true
      end

      def release(connection, key)
        true
      end
    end
    backend = described_class.new(lock: non_expiring_lock.new)
    value = Random.new(RSpec.configuration.seed).bytes(64)

    backend.with_idempotency_key("no-lease") do |store|
      store.store(data: value, ttl: 300)
      expect(store.lookup).to eq(value)
    end
  end

  it "prunes expired locks as well as expired responses" do
    lock_model = subject.lock_model
    expired = described_class::TokenLock.new(ttl_seconds: -1)
    expired.acquire(ActiveRecord::Base.connection, "abandoned-key")

    expect(lock_model.count).to eq(1)
    subject.prune!
    expect(lock_model.count).to eq(0)
  end

  it "releases the lock even if the block raises" do
    expect {
      subject.with_idempotency_key("boom") { raise "kaboom" }
    }.to raise_error(/kaboom/)

    expect(subject.lock_model.count).to eq(0)
    expect { subject.with_idempotency_key("boom") { |s| s.lookup } }.not_to raise_error
  end
end
