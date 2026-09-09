class Idempo::MemoryBackend
  def initialize
    require_relative "response_store"
    @lock = Idempo::MemoryLock.new
    @response_store = Idempo::ResponseStore.new
    @store_mutex = Mutex.new
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
    @lock.with(request_key) do
      store = Store.new(store_mutex: @store_mutex, response_store: @response_store, key: request_key)
      yield(store)
    end
  end

  def prune!
    @response_store.prune
  end
end
