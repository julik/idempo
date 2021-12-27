require 'json'

class Idempo::MalformedKeyErrorApp
  def self.call(env)
    res = {
      ok: false,
      error: {
        message: "The Idempotency-Key header provided was empty or malformed"
      }
    }
    [400, {'Content-Type' => 'application/json'}, [JSON.pretty_generate(res)]]
  end
end
