## 1.5.0

- Add SQLite support to `ActiveRecordBackend`. SQLite has no advisory locks, so the backend now ships a
  `TokenLock` - a lease lock built on an atomic `INSERT ... ON CONFLICT DO UPDATE ... WHERE` into a new
  `idempo_locks` table, with a random fencing token and an expiry. It is the same scheme the `RedisBackend`
  uses, and it recovers by itself from a process killed while holding a lock. MySQL and PostgreSQL keep
  using advisory locks and are unaffected.
- Add a `rails g idempo:install` generator. It detects whether `idempo_responses` already exists and
  generates a migration for only the tables you are missing, so existing installations get a migration
  which adds `idempo_locks` alone.
- `ActiveRecordBackend.create_table` is unchanged and still creates only `idempo_responses` - migrations
  already committed against earlier versions of Idempo keep behaving exactly as before. The table
  definitions are now also available individually as `create_responses_table` and `create_locks_table`.
- `ActiveRecordBackend#prune!` also deletes abandoned lock rows.
- `ActiveRecordBackend.new` accepts a `lock:` argument to override the lock implementation. Passing
  `TokenLock` makes the backend usable through a transaction-pooling proxy such as PGBouncer, where
  connection-bound advisory locks are not.
- A response is no longer written when the lock lease expired while the request was being served.

## 1.4.0

- `RequestFingerprint` is now a class instead of a module, with an overridable `extract_user_identity` method.
  The default implementation uses the `Authorization` header when present, and falls back to the Rails session
  cookie (`_<appname>_session`) when it is not. This prevents cross-user response leakage for apps using
  cookie-based authentication. For custom auth mechanisms, subclass `RequestFingerprint` and override
  `extract_user_identity`. Backward compatible — the class still works as the default `compute_fingerprint_via:` value.

## 1.3.1

- Instead of retaining the ActiveRecord connection in Idempo operations, check it out temporarily from the AR pool.
  This should improve interop with fibers/Async.

## 1.3.0

- Streamline integration with both Rack 2 and 3, add tests for request fingerprinting.

## 1.2.2

- Support `#to_ary` on Rack response bodies on newer Rails/Rack versions

## 1.2.1

- Use autoloading for internal modules. A user using Redis does not have to load the ActiveRecord storage backend, for example
- Ensure that the original Rack response body receives a `close` when reading out for caching

## 1.2.0

- Use memory locking in addition to DB locking in `ActiveRecordBackend`

## 1.1.0

- Use modern ActiveRecord migration options for better Rails 7.x compatibility
- Ensure Github actions CI can run and uses Postgres appropriately
- Add examples for more sophisticated use cases
- Implement `#prune!` on storage backends
- Reformat all code using [standard](https://github.com/standardrb/standard) instead of wetransfer_style as it is both more relaxed and more modern

## 1.0.0

- Release 1.0 as the API can be considered stable and the gem has been in production for years

## 0.2.0

- Allow setting the global default TTL for the cached responses
- Allow customisation of the request key computation (so that the client can decide whether to include/exclude `Authorization` and the like)
- Extract the error response generating apps into separate modules, to make them easier to override

## 0.1.0

- Initial release
