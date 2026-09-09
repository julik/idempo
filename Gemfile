# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Rack is the only runtime dependency whose major version we actively test against.
# CI pins this to exercise both Rack 2 and Rack 3; left unset it resolves to the newest.
gem "rack", ENV["RACK_VERSION"] if ENV["RACK_VERSION"]

# Native client libraries for the database servers Idempo supports. These are kept out of
# the gemspec development dependencies so that CI jobs which need no database server can
# skip them entirely.
group :db_servers do
  gem "mysql2"
  gem "pg"
  gem "redis", "~> 4"
end
