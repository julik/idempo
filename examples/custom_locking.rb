# Sometimes you might need a different locking strategy than advisory locks,
# but still use the database-backed storage for idempotent responses. This can arise
# if you are using pgbouncer for instance, where advisory locks are not available
# when using the "transaction mode". You can modify the backend to use a different
# locking mechanism, but keep the rest.

class ActiveRecordBackendWithDistributedLock < Idempo::ActiveRecordBackend
  class LocksViaService
    def acquire(_conn, based_on_str)
      LockingService.acquire("idempo-lk-#{based_on_str}")
    end

    def release(_conn, based_on_str)
      LockingService.release("idempo-lk-#{based_on_str}")
      true
    end
  end

  def lock_implementation_for_connection(_connection)
    LocksViaService.new
  end
end
