RSpec.shared_examples "a TokenLock" do
  let(:lock_key) { "some-request-fingerprint" }
  let(:connection) { ActiveRecord::Base.connection }

  # Some databases keep their tables for the whole file, and a lease taken over in one
  # example would otherwise still be held in the next one
  before { described_class.new.lock_model.delete_all }

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
    backend = described_class.new(lock: described_class::TokenLock.new)

    expect {
      backend.with_idempotency_key(lock_key) { |store| store.lookup }
    }.to raise_error(Idempo::ConcurrentRequest)

    squatter.release(connection, lock_key)
    expect { backend.with_idempotency_key(lock_key) { |store| store.lookup } }.not_to raise_error
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

  # One instance passed via `lock:` serves every request of the process. Requests with
  # different keys run concurrently (the MemoryLock only rejects a repeated key), so the
  # lease of one key must not be lost when another key gets acquired in the meantime.
  it "keeps the lease of every key when one instance is shared by concurrent requests" do
    rng = Random.new(RSpec.configuration.seed)
    first_value, second_value = rng.bytes(128), rng.bytes(128)
    lock = described_class::TokenLock.new
    backend = described_class.new(lock: lock)

    backend.with_idempotency_key("first-key") do |first_store|
      backend.with_idempotency_key("second-key") do |second_store|
        expect(lock.held?(connection, "first-key")).to eq(true)
        expect(lock.held?(connection, "second-key")).to eq(true)

        second_store.store(data: second_value, ttl: 300)
        expect(second_store.lookup).to eq(second_value)
      end

      expect(lock.held?(connection, "first-key")).to eq(true)
      first_store.store(data: first_value, ttl: 300)
      expect(first_store.lookup).to eq(first_value)
    end

    expect(backend.lock_model.count).to eq(0)
  end
end
