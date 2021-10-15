RSpec.shared_examples "a backend for Idempo" do

  it 'does not return a nonexistent value' do
    random_key = Random.new(RSpec.configuration.seed).bytes(12)
    expect(subject.lookup(random_key)).to be_nil
  end

  it 'stores a value and then returns it' do
    random_key = Random.new(RSpec.configuration.seed).bytes(8)
    value = Random.new(RSpec.configuration.seed).bytes(1209)

    subject.store(random_key, value, _ttl = 0.8)
    expect(subject.lookup(random_key)).to eq(value)
  end

  it 'shortens the expiry of a value if stored twice with a shorter expiry' do
    random_key = Random.new(RSpec.configuration.seed).bytes(8)
    value = Random.new(RSpec.configuration.seed).bytes(1209)

    subject.store(random_key, value, _ttl = 400)
    subject.store(random_key, value, _ttl = 0.8)
    sleep 1
    expect(subject.lookup(random_key)).to be_nil
  end

  it 'does not return a value after it expires' do
    random_key = Random.new(RSpec.configuration.seed).bytes(11)
    value = Random.new(RSpec.configuration.seed).bytes(1209)

    subject.store(random_key, value, _ttl = 0.8)
    sleep 1
    expect(subject.lookup(random_key)).to be_nil
  end

  it 'provides locking' do
    a, b, c = (1..3).map do
      Fiber.new do
        subject.with_lock("first") do
          Fiber.yield(:lock_held)
        end
      end
    end

    expect(a.resume).to eq(:lock_held)
    expect {
      b.resume
    }.to raise_error(Idempo::ConcurrentRequest)
    expect {
      a.resume
    }.not_to raise_error

    expect(c.resume).to eq(:lock_held)
    expect {
      c.resume
    }.not_to raise_error
  end
end
