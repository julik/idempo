# This backend currently only works with mysql2 since it uses advisory locks
class Idempo::ActiveRecordBackend
  def self.create_table(via_migration)
    via_migration.create_table 'idempo_responses', charset: 'utf8mb4', collation: 'utf8mb4_unicode_ci' do |t|
      t.string :idempotent_request_key, index: true, unique: true, null: false
      t.datetime :expire_at, index: true, null: false # Needs an index for cleanup
      t.binary :idempotent_response_payload, size: :medium
      t.timestamps
    end
  end

  class Store < Struct.new(:key, :model)
    def lookup
      model.where(idempotent_request_key: key).where('expire_at > ?', Time.now).first&.idempotent_response_payload
    end

    def store(data:, ttl:)
      # MySQL does not support datetime with subsecont precision, so ceil() it is
      expire_at = Time.now.utc + ttl.ceil
      model.transaction do
        model.where(idempotent_request_key: key).delete_all
        model.create(idempotent_request_key: key, idempotent_response_payload: data, expire_at: expire_at)
      end
      true
    end
  end

  class PostgresLock
    def acquire(conn, based_on_str)
      acquisition_result = conn.select_value('SELECT pg_try_advisory_lock(%d)' % derive_lock_key(based_on_str))
      [true, 't'].include?(acquisition_result)
    end

    def release(conn, based_on_str)
      conn.select_value('SELECT pg_advisory_unlock(%d)' % derive_lock_key(based_on_str))
    end

    def derive_lock_key(from_str)
      # The key must be a single bigint (signed long)
      hash_bytes = Digest::SHA1.digest(from_str)
      hash_bytes[0...8].unpack('l_').first
    end
  end

  class MysqlLock
    def acquire(connection, based_on_str)
      did_acquire = connection.select_value("SELECT GET_LOCK(%s, %d)" % [connection.quote(derive_lock_name(based_on_str)), 0])
      did_acquire == 1
    end

    def release(connection, based_on_str)
      connection.select_value("SELECT RELEASE_LOCK(%s)" % connection.quote(derive_lock_name(based_on_str)))
    end

    def derive_lock_name(from_str)
      db_safe_key = Base64.strict_encode64(from_str)
      "idempo_%s" % db_safe_key[0...57] # Note there is a limit of 64 bytes on the lock name
    end
  end

  def initialize
    require 'active_record'
  end

  # Allows the model to be defined lazily without having to require active_record when this module gets loaded
  def model
    @model_class ||= Class.new(ActiveRecord::Base) do
      self.table_name = 'idempo_responses'
    end
  end

  def with_idempotency_key(request_key)
    db_safe_key = Digest::SHA1.base64digest(request_key)
    lock = lock_implementation_for_connection(model.connection)

    raise Idempo::ConcurrentRequest unless lock.acquire(model.connection, request_key)

    begin
      yield(Store.new(db_safe_key, model))
    ensure
      lock.release(model.connection, request_key)
    end
  end

  private

  def lock_implementation_for_connection(connection)
    if connection.adapter_name =~ /^mysql2/i
      MysqlLock.new
    elsif connection.adapter_name =~ /^postgres/i
      PostgresLock.new
    else
      raise "Unsupported database driver #{model.connection.adapter_name.downcase} - we don't know whether it supports advisory locks"
    end
  end
end
