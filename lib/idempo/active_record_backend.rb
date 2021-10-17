require 'active_record'

class Idempo::ActiveRecordBackend
  def self.create_table(via_migration)
    via_migration.create_table 'idempo_responses', charset: 'utf8mb4', collation: 'utf8mb4_unicode_ci' do |t|
      t.string :idempotent_request_key, index: true, unique: true, null: false
      t.datetime :expire_at, index: true, null: false
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

  # Allows the model to be defined lazily without having to require active_record when this module gets loaded
  def model
    @model_class ||= Class.new(ActiveRecord::Base) do
      self.table_name = 'idempo_responses'
    end
  end

  def with_idempotency_key(request_key)
    db_safe_key = Base64.strict_encode64(request_key)

    lock_name = "idempo_%s" % db_safe_key[0..48]
    quoted_lock_name = model.connection.quote(lock_name) # Note there is a limit of 64 bytes on the lock name
    did_acquire = model.connection.select_value("SELECT GET_LOCK(%s, %d)" % [quoted_lock_name, 0])

    raise Idempo::ConcurrentRequest unless did_acquire == 1

    begin
      yield(Store.new(db_safe_key, model))
    ensure
      model.connection.select_value("SELECT RELEASE_LOCK(%s)" % quoted_lock_name)
    end
  end
end
