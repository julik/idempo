class Idempo::RedisBackend
  # The TTL value for the lock, which is used if the process
  # holding the lock crashes or gets killed
  LOCK_TTL_SECONDS = 5 * 60

  # See https://redis.io/topics/distlock
  DELETE_BY_KEY_AND_VALUE_SCRIPT = <<~EOL
    if redis.call("get",KEYS[1]) == ARGV[1] then
      return redis.call("del",KEYS[1])
    else
      return 0
    end
  EOL

  def initialize(redis_or_connection_pool)
    require 'redis'
    require 'digest'
    @redis_or_pool = redis_or_connection_pool
    @script_sha = Digest::SHA1.hexdigest(DELETE_BY_KEY_AND_VALUE_SCRIPT)
  end

  def with_lock(request_key)
    lock_key = "idempo:lock:#{request_key}"
    token = Random.new.bytes(32)
    did_acquire = with_redis { |r| r.set(lock_key, token, nx: true, ex: LOCK_TTL_SECONDS) }

    raise Idempo::ConcurrentRequest unless did_acquire

    begin
      yield
    ensure
      delete_token_using_lua_script(lock_key, token)
    end
  end

  # @return [String] binary data with serialized response
  def lookup(request_key)
    response_redis_key = "idempo:response:#{request_key}"
    with_redis do |r|
      bin_str = r.get(response_redis_key)
      bin_str&.force_encoding(Encoding::BINARY)
    end
  end

  def store(request_key, binary_data, ttl)
    response_redis_key = "idempo:response:#{request_key}"
    ttl_millis = (ttl * 1000.0).round
    with_redis { |r| r.set(response_redis_key, binary_data.force_encoding(Encoding::BINARY), px: ttl_millis) }
  end

  private

  def delete_token_using_lua_script(lock_key, token)
    with_redis do |r|
      begin
        r.evalsha(@script_sha, keys: [lock_key], argv: [token])
      rescue Redis::CommandError => e
        if e.message.include? "NOSCRIPT"
          r.script(:load, DELETE_BY_KEY_AND_VALUE_SCRIPT)
          retry
        else
          raise e
        end
      end
    end
  end

  def with_redis
    if @redis_or_pool.respond_to?(:with)
      @redis_or_pool.with {|r| yield(r) }
    else
      yield @redis_or_pool
    end
  end
end
