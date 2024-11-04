# frozen_string_literal: true

require "rack/test"
require "rack/lint"
require "spec_helper"

RSpec.describe Idempo do
  it "has a version number" do
    expect(Idempo::VERSION).not_to be nil
  end

  include Rack::Test::Methods

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

  describe "with a very large response body" do
    let(:app) do
      the_app = ->(env) {
        pre_sized_body = PreSizedBody.new(999999999)
        [200, {"x-foo" => "bar", "content-length" => "999999999"}, pre_sized_body]
      }
      Rack::Lint.new(Idempo.new(the_app, backend: Idempo::MemoryBackend.new))
    end

    it "does not provide idempotency for POST requests" do
      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      first_response_body = last_response.body

      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      expect(last_response.body).not_to eq(first_response_body) # response should not have been reused
    end
  end

  describe "with a response body that supports only 'to_ary'" do
    body_class = Class.new do
      def to_ary
        ["one", "two", Random.new.bytes(8)]
      end

      def each
        raise "Should never be called because if to_ary is used each is ignored"
      end

      def close
        raise "Should never be called because if to_ary is used it is assumed to have closed by itself"
      end
    end

    let(:app) do
      the_app = ->(env) {
        [200, {"x-foo" => "bar"}, body_class.new]
      }
      Idempo.new(the_app, backend: Idempo::MemoryBackend.new)
    end

    it "provides idempotency for POST requests and correctly persists the body" do
      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      first_response_body = last_response.body
      expect(first_response_body).to start_with("one")

      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      expect(last_response.body).to eq(first_response_body) # Response should be reused
    end
  end

  describe "with a very large response body which is materialized into an array of strings" do
    let(:app) do
      the_app = ->(_env) {
        big_blob = Random.new.bytes(5 * 1024 * 1024)
        [200, {"x-foo" => "bar"}, [Random.new.bytes(13), big_blob]]
      }
      Rack::Lint.new(Idempo.new(the_app, backend: Idempo::MemoryBackend.new))
    end

    it "does not provide idempotency for POST requests" do
      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      first_response_body = last_response.body

      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      expect(last_response.body).not_to eq(first_response_body) # response should not have been reused
    end
  end

  describe "when no double requests are in progress" do
    let(:app) do
      the_app = ->(env) {
        body = if env["REQUEST_METHOD"] == "HEAD"
          []
        else
          [Random.new.bytes(15), env["rack.input"]&.read]
        end

        [200, {"x-foo" => "bar"}, body]
      }
      Rack::Lint.new(Idempo.new(the_app, backend: Idempo::MemoryBackend.new))
    end

    it "provides idempotency for POST requests" do
      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      first_response_body = last_response.body

      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      expect(last_response.body).to eq(first_response_body) # response should have been reused
    end

    it "provides idempotency for POST requests with the same HTTP auth" do
      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem", "HTTP_AUTHORIZATION" => "Bearer abc"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      first_response_body = last_response.body

      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem", "HTTP_AUTHORIZATION" => "Bearer abc"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      expect(last_response.body).to eq(first_response_body) # response should have been reused
    end

    it "adds the Authorization: header to the idempotency key fingerprint" do
      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem", "HTTP_AUTHORIZATION" => "Bearer abc"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      first_response_body = last_response.body

      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem", "HTTP_AUTHORIZATION" => "Bearer mno"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      expect(last_response.body).not_to eq(first_response_body) # response should not have been reused
    end

    it "provides idempotency for POST requests with both quoted and unquoted header value" do
      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => '"idem"'
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      first_response_body = last_response.body

      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      expect(last_response.body).to eq(first_response_body) # response should have been reused
    end

    it "responds with a 400 if the idempotency key header is provided but empty" do
      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => '""'
      expect(last_response).to be_bad_request

      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => ""
      expect(last_response).to be_bad_request
    end

    it "is not idempotent if the HTTP verb is different" do
      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      first_response_body = last_response.body

      patch "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.body).not_to eq(first_response_body) # response should not have been reused
    end

    it "is not idempotent if the request body is different" do
      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      first_response_body = last_response.body

      post "/", "somedata2", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      expect(last_response.body).not_to eq(first_response_body) # response should not have been reused
    end

    it "is not idempotent if the URL is different" do
      post "/some", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      first_response_body = last_response.body

      post "/another", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      expect(last_response.body).not_to eq(first_response_body) # response should not have been reused
    end

    it "is not saved if the request is a GET" do
      get "/some", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      first_response_body = last_response.body

      get "/some", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      expect(last_response.body).not_to eq(first_response_body) # response should not have been reused
    end

    it "is not saved if the request is a HEAD" do
      head "/some", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      first_response_body = last_response.body

      head "/some", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      expect(last_response.body).not_to eq(first_response_body) # response should not have been reused
    end

    it "is not idempotent without the idempotency key" do
      post "/", "somedata"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      first_response_body = last_response.body

      post "/", "somedata"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      expect(last_response.body).not_to eq(first_response_body) # response should not have been reused
    end

    context "with side effects" do
      let(:app) do
        @counter = 0
        the_app = ->(_env) {
          @counter += 1
          [200, {}, [Random.new.bytes(15)]]
        }
        Rack::Lint.new(Idempo.new(the_app, backend: Idempo::MemoryBackend.new))
      end

      it "only executes the side effect once" do
        post "/", "", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
        post "/", "", "HTTP_X_IDEMPOTENCY_KEY" => "idem"

        expect(@counter).to eq(1)
      end
    end
  end

  describe "with an application that asks the idempotent request not to be stored" do
    let(:app) do
      the_app = ->(env) {
        [200, {"X-Idempo-Policy" => "no-store"}, [Random.new.bytes(15), env["rack.input"].read]]
      }
      Rack::Lint.new(Idempo.new(the_app, backend: Idempo::MemoryBackend.new))
    end

    it "does not retain the request" do
      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      fist_response_body = last_response.body

      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.body).not_to eq(fist_response_body)
    end
  end

  describe "with an application that specifies the TTL for the idempotent request" do
    let(:app) do
      the_app = ->(env) {
        [200, {"X-Idempo-Persist-For-Seconds" => "2"}, [Random.new.bytes(15), env["rack.input"].read]]
      }
      Rack::Lint.new(Idempo.new(the_app, backend: Idempo::MemoryBackend.new))
    end

    it "sets the expires_after to the requisite value" do
      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      fist_response_body = last_response.body

      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.body).to eq(fist_response_body)

      sleep 2

      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      expect(last_response).to be_ok
      expect(last_response.body).not_to eq(fist_response_body)
    end
  end

  describe "with non-idempotent response HTTP status codes" do
    let(:app) do
      the_app = ->(env) {
        overridden_status = env.fetch("HTTP_STATUS_OVERRIDE").to_i
        [overridden_status, {"x-foo" => "bar"}, [Random.new.bytes(15)]]
      }
      Rack::Lint.new(Idempo.new(the_app, backend: Idempo::MemoryBackend.new))
    end

    it "does not save the response for 5xx responses" do
      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem", "HTTP_STATUS_OVERRIDE" => "500"
      expect(last_response).not_to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      first_response_body = last_response.body

      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem", "HTTP_STATUS_OVERRIDE" => "200"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      expect(last_response.body).not_to eq(first_response_body) # response should not have been reused
    end

    it "does not save the response for 425 responses" do
      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem", "HTTP_STATUS_OVERRIDE" => "425"
      expect(last_response).not_to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      first_response_body = last_response.body

      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem", "HTTP_STATUS_OVERRIDE" => "200"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      expect(last_response.body).not_to eq(first_response_body) # response should not have been reused
    end

    it "does not save the response for 429 responses" do
      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem", "HTTP_STATUS_OVERRIDE" => "429"
      expect(last_response).not_to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      first_response_body = last_response.body

      post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem", "HTTP_STATUS_OVERRIDE" => "200"
      expect(last_response).to be_ok
      expect(last_response.headers["x-foo"]).to eq("bar")
      expect(last_response.body).not_to eq(first_response_body) # response should not have been reused
    end
  end

  describe "with an application that raises an exception" do
    let(:app) do
      the_app = ->(_env) {
        raise "Something bad happened"
      }
      Rack::Lint.new(Idempo.new(the_app, backend: Idempo::MemoryBackend.new))
    end

    it "re-raises the exception" do
      expect {
        post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
      }.to raise_error(/bad happened/)
    end
  end

  describe "with a double request" do
    let(:app) do
      the_app = ->(_env) {
        Fiber.yield
        [200, {}, ["Hello from slow request"]]
      }
      Rack::Lint.new(Idempo.new(the_app, backend: Idempo::MemoryBackend.new))
    end

    it "responds to a concurrent request with a 429" do
      first_request = Fiber.new do
        post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
        expect(last_response).to be_ok
      end
      second_request = Fiber.new do
        # The same request which is happening concurrently
        post "/", "somedata", "HTTP_X_IDEMPOTENCY_KEY" => "idem"
        expect(last_response.status).to eq(429)
      end

      first_request.resume # Start the first (slow) request
      second_request.resume # Start the second (fast) request which will terminate with a 425
      expect {
        second_request.resume
      }.to raise_error(FiberError) # The second request fiber does not yield and terminates immediately, and contains an assertion (which should pass)

      first_request.resume
      expect(last_response).to be_ok # The response from the long request is saved last
    end
  end
end
