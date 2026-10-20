# A memory lock prevents multiple requests with the same request
# fingerprint from running concurrently
class Idempo::MemoryLock
  def initialize
    @requests_in_flight_mutex = Mutex.new
    @in_progress = Set.new
  end

  def with(request_key)
    @requests_in_flight_mutex.synchronize do
      if @in_progress.include?(request_key)
        raise Idempo::ConcurrentRequest
      else
        @in_progress << request_key
      end
    end

    # Only the request which got the key in may remove it again - a rejected request
    # must leave the key of the request still in flight alone
    begin
      yield
    ensure
      @requests_in_flight_mutex.synchronize { @in_progress.delete(request_key) }
    end
  end
end
