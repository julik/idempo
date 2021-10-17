class Idempo::RedisBackend
  # The TTL value for the lock, which is used if the process
  # holding the lock crashes or gets killed
  LOCK_TTL_SECONDS = 5 * 60

  # See https://redis.io/topics/distlock
  DELETE_BY_KEY_AND_VALUE_SCRIPT = <<~EOL
    if redis.call("get",KEYS[1]) == ARGV[1] then
      -- we are still holding the lock, release it
      redis.call("del",KEYS[1])
      return "ok"
    else
      -- someone else holds the lock or it has expired
      return "lock_lost"
    end
  EOL

  # See https://redis.io/topics/distlock
  SET_WITH_TTL_IF_LOCK_STILL_HELD_SCRIPT = <<~EOL
    if redis.call("get", KEYS[1]) == ARGV[1] then
      -- we are still holding the lock, we can go ahead and set it
      redis.call("set", KEYS[2], ARGV[2], "px", ARGV[3])
      return "ok"
    else
      return "lock_lost"
    end
  EOL

  class Store < Struct.new(:redis_pool, :key, :lock_redis_key, :lock_token, keyword_init: true)
    def lookup
      response_redis_key = "idempo:response:#{key}"
      redis_pool.with do |r|
        bin_str = r.get(response_redis_key)
        bin_str&.force_encoding(Encoding::BINARY)
      end
    end

    def store(data:, ttl:)
      response_redis_key = "idempo:response:#{key}"
      ttl_millis = (ttl * 1000.0).round

      # We save our payload using a script, and we will _only_ save it if our lock is still held.
      # If our lock expires during the request - for example our app.call takes too long -
      # we might have lost it, and another request has already saved a payload on our behalf. At this point
      # we have no guarantee that our response was generated exclusively, or that the response that was generated
      # by our "competitor" is equal to ours, or that a "competing" request is not holding our lock and executing the
      # same workload as we just did. The only sensible thing to do when we encounter this is to actually _skip_ the write.
      keys = [lock_redis_key, response_redis_key]
      argv = [lock_token, data.force_encoding(Encoding::BINARY), ttl_millis]
      redis_pool.with do |r|
        r.eval(SET_WITH_TTL_IF_LOCK_STILL_HELD_SCRIPT, keys: keys, argv: argv)
      end
    end
  end

  class NullPool < Struct.new(:redis)
    def with
      yield redis
    end
  end

  def initialize(redis_or_connection_pool)
    require 'redis'
    require 'securerandom'
    @redis_pool = redis_or_connection_pool.respond_to?(:with) ? redis_or_connection_pool : NullPool.new(redis_or_connection_pool)
  end

  def with_idempotency_key(request_key)
    lock_key = "idempo:lock:#{request_key}"
    token = SecureRandom.bytes(32)
    did_acquire = @redis_pool.with { |r| r.set(lock_key, token, nx: true, ex: LOCK_TTL_SECONDS) }

    raise Idempo::ConcurrentRequest unless did_acquire

    begin
      store = Store.new(redis_pool: @redis_pool, lock_redis_key: lock_key, lock_token: token, key: request_key)
      yield(store)
    ensure
      @redis_pool.with do |r|
        r.eval(DELETE_BY_KEY_AND_VALUE_SCRIPT, keys: [lock_key], argv: [token])
      end
    end
  end
end
