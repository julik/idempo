# Idempo

A relatively straightforward idempotency keys gem. If your client sends the `Idempotency-Key` or `X-Idempotency-Key` header to your Rack
application, and the response can be cached, Idempo will provide both a concurrent request lock and a cache for idempotent responses. If
the idempotent response is already saved for this idempotency key and request fingerprint, the cached response is going to be served
instead of calling your application.

## Usage

Idempo supports a number of backends, we recommend using Redis if you have multiple application servers / dynos, the ActiveRecordBackend if you would rather not run Redis just for this (it works with MySQL, PostgreSQL and SQLite), and MemoryBackend if you are only using one single Puma worker. To initialize with Redis as backend pass the `backend:` parameter when adding the middleware:

```ruby
be = Idempo::RedisBackend.new(Rails.application.config.redis_connection_pool)
use Idempo, backend: be
```

and to initialize with a memory store as backend:

```ruby
use Idempo
```

In principle, the following requests qualify to be cached used the idempotency key:

* Any request which is not a `GET`, `HEAD` or `OPTIONS` and...
* Provides an `Idempotency-Key` or `X-Idempotency-Key` header

The default time for storing the cache is 30 seconds from the moment the request has finished generating. The response is going to be buffered, then serialized using msgpack, then deflated. Idempo will not cache the response if its size cannot be known in advance, and if the size of the response body exceeds a reasonable size (4 MB is our limit for the time being) - this is to prevent your storage from filling up with very large responses.

## Controlling the behavior of Idempo from your application

You can control the behavior of Idempo using special response headers:

* Set `X-Idempo-Policy` to `no-store` to disable retention of the response even though it otherwise could be cached
* Set `X-Idempo-Persist-For-Seconds` to a decimal number of seconds to store your response for. If your response contains time-sensitive data you might need to tweak the storage time.

Idempo supports a number of data stores (here they are called "backends") - `MemoryBackend`, `ActiveRecordBackend`, `RedisBackend`.

## Using memory for idempotency keys

If you run only one Puma on one server (so multiple threads but one process) the `MemoryBackend` will work fine for you.

* It uses a `Set` with a `Mutex` around it to store requests in progress
* It uses a sorted array for expiration and cached responses.

Needless to say, if your server terminates or restarts all the data disappears with it. This backend will also only work if you are running one Puma process (or other single-process server, and just one instance of it). 

## Using your database for idempotency keys (via ActiveRecord)

The relational database you already have is a perfectly fine place to store idempotency key locks and responses. Idempo supports MySQL, PostgreSQL and SQLite. Idempo stores its data in two tables - `idempo_responses` and `idempo_locks` - and ships a generator which creates the migration for them:

```bash
$ rails g idempo:install
$ rails db:migrate
```

If you are already using Idempo you will have the `idempo_responses` table from an earlier version. The generator detects this and writes a migration which only adds the table you are missing:

```
$ rails g idempo:install
      idempo  idempo_responses is already present, creating idempo_locks only
      create  db/migrate/20240115120000_add_idempo_locks.rb
```

Detection queries your database, and falls back to reading `db/schema.rb` (or `db/structure.sql`) when there is no database to connect to. You can always override it with `--locks-only` or `--no-locks-only`.

If you would rather write the migration by hand, the two table definitions are available separately. For a new installation:

```ruby
class InstallIdempo < ActiveRecord::Migration[7.0]
  def change
    Idempo::ActiveRecordBackend.create_responses_table(self)
    Idempo::ActiveRecordBackend.create_locks_table(self)
  end
end
```

and for an installation which already has `idempo_responses`:

```ruby
class AddIdempoLocks < ActiveRecord::Migration[7.0]
  def change
    Idempo::ActiveRecordBackend.create_locks_table(self)
  end
end
```

`Idempo::ActiveRecordBackend.create_table` still creates just `idempo_responses`, exactly as it did in earlier versions - migrations you have already committed keep working and keep meaning the same thing.

Then configure Idempo to use the backend (in your `application.rb`):

```ruby
be = Idempo::ActiveRecordBackend.new
config.middleware.insert Idempo, backend: be
```

In your regular tasks (cron or Rake) you will want to add a call to delete old Idempo responses and abandoned locks (both tables have an index on `expire_at`):

```ruby
Idempo::ActiveRecordBackend.new.prune!
```

### How locking works per database

Idempo picks the locking strategy from your database adapter:

* **MySQL** uses `GET_LOCK` / `RELEASE_LOCK` advisory locks
* **PostgreSQL** uses `pg_try_advisory_lock` / `pg_advisory_unlock` advisory locks
* **SQLite** has no advisory locks, so it uses the `TokenLock` - see below

Advisory locks are held by the database connection, so they are released the moment the connection goes away - which makes them ideal, but also makes them unusable through a transaction-pooling proxy such as PGBouncer. If that is your setup, pass the `TokenLock` explicitly:

```ruby
be = Idempo::ActiveRecordBackend.new(lock: Idempo::ActiveRecordBackend::TokenLock.new)
```

### Using SQLite

SQLite has no advisory locks and only one writer at a time, but it does apply a single `INSERT ... ON CONFLICT DO UPDATE ... WHERE` statement atomically - and that is all a lease lock needs. The `TokenLock` inserts a row with a random fencing token into `idempo_locks`; the unique index on the request key is what makes the acquisition mutually exclusive. It is the same scheme the `RedisBackend` uses (`SET NX PX` plus a token), only expressed in SQL:

* Acquiring the lock is one statement which inserts when no lock row exists, overwrites the row when the previous lease has expired, and does nothing at all when somebody else holds the lock. Idempo then raises `ConcurrentRequest`, exactly like it does for a contended advisory lock.
* The lock row carries an expiry (`Idempo::ActiveRecordBackend::LOCK_TTL_SECONDS`, 5 minutes by default), so a lock left behind by a killed process gets taken over by a later request instead of wedging that idempotency key forever.
* Releasing deletes only a row still carrying our own token, so we never release a lock somebody else has taken over.
* If the lease does expire while your `app.call` is still running, the response is not written at all - another request may have generated a different response under the same key in the meantime, and overwriting it would be worse than not caching.

Nothing beyond the migration is required, but two settings in your `database.yml` are worth having:

```yaml
production:
  adapter: sqlite3
  database: storage/production.sqlite3
  timeout: 5000  # Wait up to 5s for the write lock instead of raising SQLITE_BUSY
```

and WAL mode, so that reading a cached response does not block on the process currently writing one:

```ruby
# config/initializers/sqlite.rb, if your Rails version does not do this already
ActiveRecord::Base.connection.execute("PRAGMA journal_mode=WAL") if ActiveRecord::Base.connection.adapter_name.match?(/sqlite/i)
```

Rails 7.1 and newer set `journal_mode=WAL` for new applications by default, and starting with Rails 7.1 the SQLite adapter also opens write transactions with `BEGIN IMMEDIATE`. Idempo does not depend on either - it orders the statements in its write transaction so that the write lock is taken by the first statement - but WAL will make a meaningful difference to your throughput.

## Using Redis for idempotency keys

Redis is a near-perfect data store for idempotency keys, but it can have race conditions with locks if your application runs for too long or crashes very often. If you have Redis, initialize Idempo using the `RedisBackend`:

```ruby
use Idempo, backend: Idempo::RedisBackend.new
```

If you have a configured Redis connection pool (and you should) - pass it to the initializer:

```ruby
be = Idempo::RedisBackend.new(config.redis_connection_pool)
config.middleware.insert Idempo, backend: be
```

All data stored in Redis will have TTLs and will expire automatically. Redis scripts ensure that updates to the stored idempotent responses and locking happen atomically.


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'idempo'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install idempo

## More advanced use cases

Check out the files in the `examples/` directory to see a few customisations you can do.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/julik/idempo.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
