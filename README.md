# Idempo

A relatively straightforward idempotency keys gem. If your client sends the `Idempotency-Key` or `X-Idempotency-Key` header to your Rack
application, and the response can be cached, Idempo will provide both a concurrent request lock and a cache for idempotent responses. If
the idempotent response is already saved for this idempotency key and request fingerprint, the cached response is going to be served
instead of calling your application.

## Usage

Idempo supports a number of backends, we recommend using Redis if you have multiple application servers / dynos and MemoryBackend if you are only using one single Puma worker. To initialize with Redis as backend pass the `backend:` parameter when adding the middleware:

```ruby
use Idempo, backend: Idempo::RedisBackend.new(Rails.application.config.redis_connection_pool)
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

The relational database you already have is a perfectly fine place to store idempotency key locks and responses. A requirement for that is that your database supports some form of advisory locking - both PostgreSQL and MySQL do. First you will need to create a table for the records. The table is going to be called `idempo_responses`, and you need to add a migration in your Rails project for it:

```bash
$ rails g migration add_idempo_responses
```

and then add a migration like this:

```ruby
class AddIdempoResponses < ActiveRecord::Migration[7.0]
  def change
    Idempo::ActiveRecordBackend.create_table(self)
  end
end
```

Then configure Idempo to use the backend (in your `application.rb`):

```ruby
config.middleware.insert Idempo, backend: Idempo::ActiveRecordBackend.new
```

In your regular tasks (cron or Rake) you will want to add a call to delete old Idempo responses (there is an index on `expire_at`):

```ruby
Idempo::ActiveRecordBackend.new.model.where('expire_at < ?', Time.now).in_batches.delete_all
```

If you need to use Idempo with PGBouncer you will need to write your own locking implementation based on fencing tokens or similar.

## Using Redis for idempotency keys

Redis is a near-perfect data store for idempotency keys, but it can have race conditions with locks if your application runs for too long or crashes very often. If you have Redis, initialize Idempo using the `RedisBackend`:

```ruby
use Idempo, backend: Idempo::RedisBackend.new
```

If you have a configured Redis connection pool (and you should) - pass it to the initializer:

```ruby
config.middleware.insert Idempo, backend: Idempo::RedisBackend.new(config.redis_connection_pool)
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

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/julik/idempo.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
