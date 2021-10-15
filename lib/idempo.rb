# frozen_string_literal: true

require 'zlib'
require 'msgpack'

require_relative "idempo/version"
require_relative "idempo/memory_backend"
require_relative "idempo/redis_backend"

class Idempo
  DEFAULT_TTL = 30

  class Error < StandardError; end
  class ConcurrentRequest < Error; end

  def initialize(app, backend: MemoryBackend.new)
    @backend = backend
    @app = app
  end

  def call(env)
    req = Rack::Request.new(env)
    return @app.call(env) if request_idempotent?(req)
    return @app.call(env) unless idempotency_key_header = extract_idempotency_key_from(req)

    fingerprint = compute_request_fingerprint(req)
    request_key = "#{idempotency_key_header}_#{fingerprint}"

    @backend.with_lock(request_key) do
      return from_persisted_response(response) if response = @backend.lookup(request_key)

      status, headers, body = @app.call(env)

      if response_may_be_persisted?(status, headers)
        expires_in_seconds = (headers.delete('X-Idempo-Persist-For-Seconds') || DEFAULT_TTL).to_i
        # Body is replaced with a cached version since a Rack response body is not rewindable
        marahsled_response, body = serialize_response(status, headers, body)
        @backend.save(request_key, marahsled_response, expires_in_seconds)
      end

      [status, headers, body]
    end
  rescue ConcurrentRequest
    res = {
      ok: false,
      error: {
        message: "Another request with this idempotency key is still in progress, please try again later"
      }
    }
    [429, {'Retry-After' => '2', 'Content-Type' => 'application/json'}, [JSON.pretty_generate(res)]]
  end

  def from_persisted_response(marshaled_response)
    MessagePack.unpack(Zlib.inflate(marshaled_response))
  end

  def serialize_response(status, headers, rack_response_body)
    # Buffer the Rack response body, we can only do that once (it is non-rewindable)
    body_chunks = []
    rack_response_body.each { |chunk|  body_chunks << chunk.dup }
    rack_response_body.close if rack_response_body.respond_to?(:close)

    # Only keep headers which are strings
    stringified_headers = headers.each_with_object({}) do |(header, value), filtered|
      filtered[header] = value if value.is_a?(String)
    end

    message_packed_str = MessagePack.pack([status, stringified_headers, body_chunks])
    [Zlib.deflate(message_packed_str), body_chunks]
  end

  def response_may_be_persisted?(status, headers)
    return false if headers.delete('X-Idempo-Policy') == 'no-store'

    case status
    when 200..400
      true
    when 429, 425
      false
    when 400..499
      true
    else
      false
    end
  end

  def compute_request_fingerprint(req)
    d = Digest::SHA256.new
    d << req.url
    while chunk = req.env['rack.input'].read(1024 * 65)
      d << chunk
    end
    d.hexdigest
  ensure
    req.env['rack.input'].rewind
  end

  def extract_idempotency_key_from(req)
    req['HTTP_IDEMPOTENCY_KEY'] || req['HTTP_X_IDEMPOTENCY_KEY']
  end

  def request_idempotent?(request)
    request.get? || request.head? || request.options?
  end
end
