require "json"

class Idempo::ConcurrentRequestErrorApp
  RETRY_AFTER_SECONDS = 2.to_s

  def self.call(env)
    res = {
      ok: false,
      error: {
        message: "Another request with this idempotency key is still in progress, please try again later"
      }
    }
    [429, {"Retry-After" => RETRY_AFTER_SECONDS, "Content-Type" => "application/json"}, [JSON.pretty_generate(res)]]
  end
end
