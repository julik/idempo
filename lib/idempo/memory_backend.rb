class Idempo::MemoryBackend
  def initialize
    require 'set'
    require 'thread'
    require_relative 'response_store'

    @requests_in_flight_mutex = Mutex.new
    @in_progress = Set.new
    @store_mutex = Mutex.new
    @store = Idempo::ResponseStore.new
  end

  def with_lock(request_key)
    did_insert = @requests_in_flight_mutex.synchronize do
      if @in_progress.include?(request_key)
        false
      else
        @in_progress << request_key
        true
      end
    end

    raise Idempo::ConcurrentRequest unless did_insert

    begin
      yield
    ensure
      @requests_in_flight_mutex.synchronize { @in_progress.delete(request_key) }
    end
  end

  # @return [String] binary data with serialized response
  def lookup(request_key)
    @store_mutex.synchronize do
      @store.lookup(request_key)
    end
  end

  def store(request_key, binary_data_with_serialized_response, ttl)
    @store_mutex.synchronize do
      @store.save(request_key, binary_data_with_serialized_response, ttl)
    end
  end
end
