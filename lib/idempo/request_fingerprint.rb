module Idempo::RequestFingerprint
  def self.call(idempotency_key, rack_request)
    d = Digest::SHA256.new
    d << idempotency_key << "\n"
    d << rack_request.url << "\n"
    d << rack_request.request_method << "\n"
    d << rack_request.get_header("HTTP_AUTHORIZATION").to_s << "\n"

    # Under Rack 3.0 the rack.input may or may not be rewindable (this is done to support
    # streaming HTTP request bodies). If we know a request body is rewindable we can read it
    # out in full and add it to the request fingerprint. If the request body cannot be
    # rewound, we can't really rely on it as it can be fairly large (and we want the
    # downstream app to read the request body, not us).
    if rack_request.env["rack.input"].respond_to?(:rewind)
      read_and_rewind(rack_request.env["rack.input"], d)
    end

    Base64.strict_encode64(d.digest)
  end

  def self.read_and_rewind(source_io, to_destination_io)
    while (chunk = source_io.read(1024 * 65))
      to_destination_io << chunk
    end
  ensure
    source_io.rewind
  end
end
