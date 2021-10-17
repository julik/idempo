class Idempo::MemoryBackend
  def initialize
    require 'set'
    require_relative 'response_store'

    @requests_in_flight_mutex = Mutex.new
    @in_progress = Set.new
    @store_mutex = Mutex.new
    @response_store = Idempo::ResponseStore.new
  end

  class Store < Struct.new(:store_mutex, :response_store, :key, keyword_init: true)
    def lookup
      store_mutex.synchronize do
        response_store.lookup(key)
      end
    end

    def store(data:, ttl:)
      store_mutex.synchronize do
        response_store.save(key, data, ttl)
      end
    end
  end

  def with_idempotency_key(request_key)
    did_insert = @requests_in_flight_mutex.synchronize do
      if @in_progress.include?(request_key)
        false
      else
        @in_progress << request_key
        true
      end
    end

    raise Idempo::ConcurrentRequest unless did_insert

    store = Store.new(store_mutex: @store_mutex, response_store: @response_store, key: request_key)
    begin
      yield(store)
    ensure
      @requests_in_flight_mutex.synchronize { @in_progress.delete(request_key) }
    end
  end
end
