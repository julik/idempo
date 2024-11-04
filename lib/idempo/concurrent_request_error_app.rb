class Idempo::ConcurrentRequestErrorApp
  RETRY_AFTER_SECONDS = 2.to_s

  def self.call(env)
    res = {
      ok: false,
      error: {
        message: "Another request with this idempotency key is still in progress, please try again later"
      }
    }
    [429, {"retry-after" => RETRY_AFTER_SECONDS, "content-type" => "application/json"}, [JSON.pretty_generate(res)]]
  end
end
