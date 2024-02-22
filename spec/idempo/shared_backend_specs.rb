RSpec.shared_examples "a backend for Idempo" do
  it "does not return a nonexistent value" do
    random_key = Random.new(RSpec.configuration.seed).bytes(12)

    subject.with_idempotency_key(random_key) do |store|
      expect(store.lookup).to be_nil
    end
  end

  it "stores a value and then returns it" do
    random_key = Random.new(RSpec.configuration.seed).bytes(8)
    value = Random.new(RSpec.configuration.seed).bytes(1209)

    subject.with_idempotency_key(random_key) do |store|
      expect(store.lookup).to be_nil
      store.store(data: value, ttl: 0.8)
      expect(store.lookup).to eq(value)
    end
  end

  it "shortens the expiry of a value if stored twice with a shorter expiry" do
    random_key = Random.new(RSpec.configuration.seed).bytes(8)
    value = Random.new(RSpec.configuration.seed).bytes(1209)

    subject.with_idempotency_key(random_key) do |store|
      store.store(data: value, ttl: 400)
      store.store(data: value, ttl: 1)
      sleep 2
      expect(store.lookup).to be_nil
    end
  end

  it "does not return a value after it expires" do
    random_key = Random.new(RSpec.configuration.seed).bytes(11)
    value = Random.new(RSpec.configuration.seed).bytes(1209)

    subject.with_idempotency_key(random_key) do |store|
      store.store(data: value, ttl: 1)
      sleep 2
      expect(store.lookup).to be_nil
    end
  end

  it "supports pruning" do
    random_key = Random.new(RSpec.configuration.seed).bytes(11)
    value = Random.new(RSpec.configuration.seed).bytes(1209)

    subject.with_idempotency_key(random_key) do |store|
      store.store(data: value, ttl: 1)
    end
    sleep 2
    expect { subject.prune! }.not_to raise_error
  end

  it "provides locking" do
    lock_key = Random.new(RSpec.configuration.seed).bytes(14)
    a, b, c = (1..3).map do
      Fiber.new do
        subject.with_idempotency_key(lock_key) do
          Fiber.yield(:lock_held)
        end
      end
    end

    expect {
      a.resume
    }.not_to raise_error

    expect {
      b.resume
    }.to raise_error(Idempo::ConcurrentRequest)

    expect {
      a.resume
    }.not_to raise_error

    expect {
      c.resume
    }.not_to raise_error

    expect {
      c.resume
    }.not_to raise_error
  end
end
