# Sometimes authentication is done using a Bearer token with a signature, or using another token format
# which includes some form of expiration. This means that every time a request is made, the `Authorization`
# HTTP header may have a different value, and thus the request fingerprint could change every time,
# even though the idempotency key is the same.
# For this case, a custom fingerprinting function can be used. For example, if the bearer token is
# generated in JWT format by the client, it may include the `iss` (issuer) claim, identifying the
# specific device. This identifier can then be used instead of the entire Authorization header.

module FingerprinterWithIssuerClaim
  def self.call(idempotency_key, rack_request)
    d = Digest::SHA256.new
    d << idempotency_key << "\n"
    d << rack_request.url << "\n"
    d << rack_request.request_method << "\n"
    d << extract_jwt_iss_claim(rack_request) << "\n"
    while (chunk = rack_request.env["rack.input"].read(1024 * 65))
      d << chunk
    end
    Base64.strict_encode64(d.digest)
  ensure
    rack_request.env["rack.input"].rewind
  end

  def self.extract_jwt_iss_claim(rack_request)
    header_value = rack_request.get_header("HTTP_AUTHORIZATION").to_s
    return header_value unless header_value.start_with?("Bearer ")

    jwt = header_value.delete_prefix("Bearer ")
    # This is decoding without verification, but in this case it is reasonably safe
    # as we are not actually authenticating the request - just using the `iss` claim.
    # It can make the app slightly more sensitive to replay attacks but since the request
    # is idempotent, an already executed (and authenticated) request that generated a
    # cached response is reasonably safe to serve out.
    unverified_claims, _unverified_header = JWT.decode(jwt, _key = nil, _verify = false)
    unverified_claims.fetch("iss")
  rescue
    # If we fail to pick up the claim or anything else - assume the request is non-idempotent
    # as treating it otherwise may create a replay attack
    SecureRandom.bytes(32)
  end
end
