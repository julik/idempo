# frozen_string_literal: true

require "idempo"

class PreSizedBody
  def initialize(size_in_bytes, rng = Random.new)
    @rng = rng
    @bytes = size_in_bytes
  end

  def each
    buf_size = 4 * 1024 * 1024
    whole, rest = @bytes.divmod(buf_size)
    whole.times do
      yield(@rng.bytes(buf_size))
    end
    yield(@rng.bytes(rest)) if rest > 0
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
