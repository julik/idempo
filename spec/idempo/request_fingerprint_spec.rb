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
end
