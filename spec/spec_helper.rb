# frozen_string_literal: true

require "idempo"

# Uses as a Rack response body that just generates a certain
# amount of random bytes. Since we use Rack::Lint in our tests,
# it will actually check whether we are delivering the body of
# the size advertised in the content-length HTTP header. Having
# a body like this is a reasonably fast way to generate those
# arbitrary responses. It can also accept a Random object so that
# the generated body data is reproducible.
class PreSizedBody
  attr_reader :bytes
  def initialize(size_in_bytes, rng = Random.new)
    @rng = rng
    @bytes = size_in_bytes.to_i
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
