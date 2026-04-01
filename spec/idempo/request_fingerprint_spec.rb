# frozen_string_literal: true

require "spec_helper"
require_relative "shared_backend_specs"
require "redis"

RSpec.describe Idempo::RequestFingerprint do
  it "computes a stable fingerprint based on key headers and rewindable body IO" do
    rack_env = {
      "rack.input" => StringIO.new("body"),
      "SCRIPT_NAME" => "",
      "PATH_INFO" => "/hello",
      "REQUEST_METHOD" => "GET",
      "HTTP_AUTHORIZATION" => "Bearer abcdef"
    }
    request = Rack::Request.new(rack_env)
    idempotency_key = "highly idempotent"
    fingerprint = described_class.call(idempotency_key, request)

    expect(fingerprint).to eq("XPzIfs46kfah/YXrattdtIhhLBTq/724mdcCUsZ7PmY=")
  end

  it "computes a stable fingerprint based on key headers and non-rewindable body IO" do
    unrewindable_body = StringIO.new("body")
    class << unrewindable_body
      undef_method :rewind
    end

    rack_env = {
      "rack.input" => unrewindable_body,
      "SCRIPT_NAME" => "",
      "PATH_INFO" => "/hello",
      "REQUEST_METHOD" => "GET",
      "HTTP_AUTHORIZATION" => "Bearer abcdef"
    }
    request = Rack::Request.new(rack_env)
    idempotency_key = "highly idempotent"
    fingerprint = described_class.call(idempotency_key, request)

    expect(fingerprint).to eq("MdsC4Oc+Am87ue0dsOPiuF7gScgGbkYE9DKR735hZAU=")
  end

  it "takes all the key HTTP headers and the body into account" do
    combinations = {
      "rack.input" => [StringIO.new(""), StringIO.new("some body")],
      "SCRIPT_NAME" => ["script", ""],
      "PATH_INFO" => ["/hello", "/hello?one=1", ""],
      "REQUEST_METHOD" => ["GET", "POST", "PUT"],
      "HTTP_AUTHORIZATION" => ["Bearer abcdef", nil]
    }

    # Create combinations of all possible values of different headers, and
    # make sure they all produce different fingerprints
    initial_array = Array(combinations.values.first)
    product_with = combinations.values[1..]
    all_value_permutations = initial_array.product(*product_with)
    fingerprints = all_value_permutations.flat_map do |values|
      combination_of_possible_rack_env_values = combinations.keys.zip(values).to_h
      ["key1", "key2"].map do |idempotency_key|
        request = Rack::Request.new(combination_of_possible_rack_env_values)
        described_class.call(idempotency_key, request)
      end
    end

    expect(fingerprints.uniq.length).to eq(fingerprints.length)
  end

  it "uses the Authorization header when present, ignoring session cookies" do
    base_env = {
      "rack.input" => StringIO.new("body"),
      "SCRIPT_NAME" => "",
      "PATH_INFO" => "/hello",
      "REQUEST_METHOD" => "POST",
      "HTTP_AUTHORIZATION" => "Bearer same-token"
    }

    request_a = Rack::Request.new(base_env.merge("HTTP_COOKIE" => "_myapp_session=session1"))
    request_b = Rack::Request.new(base_env.merge("HTTP_COOKIE" => "_myapp_session=session2"))

    fingerprint_a = described_class.call("key1", request_a)
    fingerprint_b = described_class.call("key1", request_b)

    expect(fingerprint_a).to eq(fingerprint_b)
  end

  it "falls back to the Rails session cookie when no Authorization header is present" do
    base_env = {
      "rack.input" => StringIO.new("body"),
      "SCRIPT_NAME" => "",
      "PATH_INFO" => "/hello",
      "REQUEST_METHOD" => "POST"
    }

    request_a = Rack::Request.new(base_env.merge("HTTP_COOKIE" => "_myapp_session=abc123"))
    request_b = Rack::Request.new(base_env.merge("HTTP_COOKIE" => "_myapp_session=xyz789"))

    fingerprint_a = described_class.call("key1", request_a)
    fingerprint_b = described_class.call("key1", request_b)

    expect(fingerprint_a).not_to eq(fingerprint_b)
  end

  it "does not match non-Rails cookies as session cookies" do
    base_env = {
      "rack.input" => StringIO.new("body"),
      "SCRIPT_NAME" => "",
      "PATH_INFO" => "/hello",
      "REQUEST_METHOD" => "POST"
    }

    request_a = Rack::Request.new(base_env.merge("HTTP_COOKIE" => "tracking=abc123"))
    request_b = Rack::Request.new(base_env.merge("HTTP_COOKIE" => "tracking=xyz789"))

    fingerprint_a = described_class.call("key1", request_a)
    fingerprint_b = described_class.call("key1", request_b)

    expect(fingerprint_a).to eq(fingerprint_b)
  end

  context "with a subclass overriding extract_user_identity" do
    let(:custom_fingerprinter_class) do
      Class.new(described_class) do
        private

        def extract_user_identity(rack_request)
          rack_request.get_header("HTTP_X_USER_ID")
        end
      end
    end

    it "uses the overridden method for user identity" do
      fingerprinter = custom_fingerprinter_class.new
      base_env = {
        "rack.input" => StringIO.new("body"),
        "SCRIPT_NAME" => "",
        "PATH_INFO" => "/hello",
        "REQUEST_METHOD" => "POST"
      }

      request_a = Rack::Request.new(base_env.merge("HTTP_X_USER_ID" => "user-1"))
      request_b = Rack::Request.new(base_env.merge("HTTP_X_USER_ID" => "user-2"))

      fingerprint_a = fingerprinter.call("key1", request_a)
      fingerprint_b = fingerprinter.call("key1", request_b)

      expect(fingerprint_a).not_to eq(fingerprint_b)
    end

    it "no longer uses the authorization header" do
      fingerprinter = custom_fingerprinter_class.new
      base_env = {
        "rack.input" => StringIO.new("body"),
        "SCRIPT_NAME" => "",
        "PATH_INFO" => "/hello",
        "REQUEST_METHOD" => "POST",
        "HTTP_X_USER_ID" => "user-1"
      }

      request_a = Rack::Request.new(base_env.merge("HTTP_AUTHORIZATION" => "Bearer aaa"))
      request_b = Rack::Request.new(base_env.merge("HTTP_AUTHORIZATION" => "Bearer bbb"))

      fingerprint_a = fingerprinter.call("key1", request_a)
      fingerprint_b = fingerprinter.call("key1", request_b)

      expect(fingerprint_a).to eq(fingerprint_b)
    end
  end

  context "when used as an instance passed to compute_fingerprint_via:" do
    it "produces the same fingerprint as the class-level call" do
      fingerprinter = described_class.new
      rack_env = {
        "rack.input" => StringIO.new("body"),
        "SCRIPT_NAME" => "",
        "PATH_INFO" => "/hello",
        "REQUEST_METHOD" => "GET",
        "HTTP_AUTHORIZATION" => "Bearer abcdef"
      }
      request = Rack::Request.new(rack_env)

      class_fingerprint = described_class.call("key1", request)
      rack_env["rack.input"].rewind
      instance_fingerprint = fingerprinter.call("key1", request)

      expect(instance_fingerprint).to eq(class_fingerprint)
    end
  end

  it "calls extract_user_identity during fingerprint computation so that subclass overrides take effect" do
    fingerprinter = described_class.new
    rack_env = {
      "rack.input" => StringIO.new("body"),
      "SCRIPT_NAME" => "",
      "PATH_INFO" => "/hello",
      "REQUEST_METHOD" => "POST",
      "HTTP_AUTHORIZATION" => "Bearer token"
    }
    request = Rack::Request.new(rack_env)

    expect(fingerprinter).to receive(:extract_user_identity).with(request).and_call_original
    fingerprinter.call("key1", request)
  end
end
