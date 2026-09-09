appraise "rack-3" do
  gem "rack", ">= 3.0"
  gem "activerecord", "~> 7.0", "< 9.0"
  # railties provides Rails::Generators::Base, activerecord provides the migration
  # generator it mixes in - keep the two on the same major version
  gem "railties", "~> 7.0", "< 9.0"
end

appraise "rack-2" do
  gem "rack", ">= 2.0", "< 3.0"
  gem "activerecord", "~> 6", "< 7.0"
  gem "railties", "~> 6", "< 7.0"
end
