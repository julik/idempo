# Idempo

A relatively straightforward idempotency keys gem. If your client sends the `Idempotency-Key` or `X-Idempotency-Key` header to your Rack
application, and the response can be cached, Idempo will provide both a concurrent request lock and a cache for idempotent responses. If
the idempotent response is already saved for this idempotency key and request fingerprint, the cached response is going to be served
instead of calling your application.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'idempo'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install idempo

## Usage

Idempo supports a number of backends, we recommend using Redis if you have multiple application servers / dynos and MemoryBackend if you are only using one single Puma worker. To initialize with Redis as backend pass the `backend:` parameter when adding the middleware:

```ruby
use Idempo, backend: Idempo::RedisBackend.new(Rails.application.config.redis_connection_pool)
```

and to initialize with a memory store as backend:

```ruby
use Idempo, backend: Idempo::MemoryBackend.new
```

In principle, the following requests qualify to be cached used the idempotency key:

* Any request which is not a `GET`, `HEAD` or `OPTIONS` and...
* Provides an `Idempotency-Key` or `X-Idempotency-Key` header

The default time for storing the cache is 30 seconds from the moment the request has finished generating. The response is going to be buffered, then serialized using msgpack, then deflated. Idempo will not cache the response if its size cannot be known in advance, and if the size of the response body exceeds a reasonable size (4 MB is our limit for the time being) - this is to prevent your storage from filling up with very large responses.

## Controlling the behavior of Idempo

You can control the behavior of Idempo using special headers:

* Set `X-Idempo-Policy` to `no-store` to disable retention of the response even though it otherwise could be cached
* Set `X-Idempo-Persist-For-Seconds` to decimal number of seconds to store your response fo 

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/julik/idempo.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
