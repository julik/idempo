module Idempo::RequestFingerprint
  def self.call(idempotency_key, rack_request)
    d = Digest::SHA256.new
    d << idempotency_key << "\n"
    d << rack_request.url << "\n"
    d << rack_request.request_method << "\n"
    d << rack_request.get_header('HTTP_AUTHORIZATION').to_s << "\n"
    while chunk = rack_request.env['rack.input'].read(1024 * 65)
      d << chunk
    end
    Base64.strict_encode64(d.digest)
  ensure
    rack_request.env['rack.input'].rewind
  end
end
