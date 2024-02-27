## [1.2.1] - 2024-02-22

- Use autoloading for internal modules. A user using Redis does not have to load the ActiveRecord storage backend, for example
- Ensure that the original Rack response body receives a `close` when reading out for caching

## [1.2.0] - 2024-02-22

- Use memory locking in addition to DB locking in `ActiveRecordBackend`

## [1.1.0] - 2024-02-22

- Use modern ActiveRecord migration options for better Rails 7.x compatibility
- Ensure Github actions CI can run and uses Postgres appropriately
- Add examples for more sophisticated use cases
- Implement `#prune!` on storage backends
- Reformat all code using [standard](https://github.com/standardrb/standard) instead of wetransfer_style as it is both more relaxed and more modern

## [1.0.0] - 2023-10-27

- Release 1.0 as the API can be considered stable and the gem has been in production for years

## [0.2.0] - 2022-04-08

- Allow setting the global default TTL for the cached responses
- Allow customisation of the request key computation (so that the client can decide whether to include/exclude `Authorization` and the like)
- Extract the error response generating apps into separate modules, to make them easier to override

## [0.1.0] - 2021-10-14

- Initial release
