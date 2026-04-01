# frozen_string_literal: true

class Idempo::RequestFingerprint
  RAILS_SESSION_COOKIE_PATTERN = /\A_[a-z0-9_]+_session\z/i

  # Maintains backward compatibility: Idempo::RequestFingerprint can be passed
  # directly as the compute_fingerprint_via: value (the default) since it responds to .call.
  def self.call(idempotency_key, rack_request)
    new.call(idempotency_key, rack_request)
  end

  def call(idempotency_key, rack_request)
    d = Digest::SHA256.new
    d << idempotency_key << "\n"
    d << rack_request.url << "\n"
    d << rack_request.request_method << "\n"
    d << extract_user_identity(rack_request).to_s << "\n"

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

  # Extracts a value identifying the user from the request. This value gets
  # included in the request fingerprint hash. Without user identity in the
  # fingerprint, two different users sending the same idempotency key to the
  # same endpoint would receive each other's cached responses — leaking
  # sensitive data across user boundaries (similar to the Railway CDN caching
  # incident of March 2026, where responses keyed only on method+URL were
  # served to the wrong users).
  #
  # The default implementation tries two strategies, in order:
  #
  # 1. If an Authorization header is present (Bearer token, Basic auth, etc.),
  #    its full value is used. This is the common case for API applications.
  #    Different tokens produce different fingerprints, so requests from
  #    different users are naturally separated.
  #
  # 2. If no Authorization header is present, we look for a Rails-style session
  #    cookie (matching the pattern `_<appname>_session`). This covers the
  #    common case of Rails applications using cookie-based authentication,
  #    where the Authorization header is typically empty for all users. The
  #    encrypted session cookie value differs per user session, so it serves
  #    as a user identity signal. The cookie value is stable from the client's
  #    perspective across retries (the client resends the same cookie string
  #    until it receives a Set-Cookie with a new value), which is what matters
  #    for idempotency — the retry sends the same fingerprint as the original.
  #
  # If neither signal is available (no Authorization header and no Rails
  # session cookie), the fingerprint will only contain the idempotency key,
  # URL, method, and body. This is acceptable for unauthenticated endpoints
  # but DANGEROUS for authenticated endpoints using other identity mechanisms
  # (custom headers like X-API-Key, non-Rails session cookies, etc.).
  #
  # To handle those cases, subclass and override this method:
  #
  #   class MyFingerprint < Idempo::RequestFingerprint
  #     private
  #     def extract_user_identity(rack_request)
  #       rack_request.get_header("HTTP_X_API_KEY")
  #     end
  #   end
  #
  #   use Idempo, compute_fingerprint_via: MyFingerprint.new
  #
  def extract_user_identity(rack_request)
    auth = rack_request.get_header("HTTP_AUTHORIZATION").to_s
    return auth unless auth.empty?
    extract_rails_session_cookie(rack_request)
  end

  def extract_rails_session_cookie(rack_request)
    rack_request.cookies.each do |name, value|
      return value if name.match?(RAILS_SESSION_COOKIE_PATTERN)
    end
    nil
  end

  def read_and_rewind(source_io, to_destination_io)
    while (chunk = source_io.read(1024 * 65))
      to_destination_io << chunk
    end
  ensure
    source_io.rewind
  end
end
