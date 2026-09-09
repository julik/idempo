# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Native client libraries for the database servers Idempo supports. These are kept out of
# the gemspec development dependencies so that the CI job exercising the SQLite path can
# skip them - that path is supposed to work on a machine with no database server at all.
group :db_servers do
  gem "mysql2"
  gem "pg"
  gem "redis", "~> 4"
end
