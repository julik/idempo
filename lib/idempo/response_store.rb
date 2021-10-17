class Idempo::ResponseStore
  ExpiryHandle = Struct.new(:key, :expire_at)
  StoredResponse = Struct.new(:key, :expire_at, :payload)

  def initialize
    @values = {}
    @expiries = []
  end

  def save(key, value, expire_in)
    prune
    exp = expire_in + Process.clock_gettime(Process::CLOCK_MONOTONIC)
    res = StoredResponse.new(key, exp, value)
    expiry_handle = ExpiryHandle.new(key, exp)
    binary_insert(@expiries, expiry_handle, &:expire_at)
    @values[key] = res
  end

  def lookup(key)
    prune
    stored = @values[key]
    return unless stored
    return stored.payload if stored.expire_at > Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @values.delete(key)
    nil
  end

  private

  def prune
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    items_to_delete = remove_lower_than(@expiries, now, &:expire_at)
    items_to_delete.each do |expiry_handle|
      @values.delete(expiry_handle.key) if @values[expiry_handle.key] && @values[expiry_handle.key].expire_at < now
    end
  end

  def binary_insert(array, item, &property_getter)
    at_i = array.bsearch_index do |stored_item|
      yield(stored_item) <= yield(item)
    end
    at_i ? array.insert(at_i, item) : array.push(item)
  end

  def remove_lower_than(array, threshold_value, &property_getter)
    at_i = array.bsearch_index do |stored_item|
      yield(stored_item) <= threshold_value
    end
    if at_i
      array[at_i..array.length].tap do |_deleted_items|
        array.replace(array[0..at_i])
      end
    else
      []
    end
  end
end
