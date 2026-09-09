# ActiveRecord and railties are deliberately left unpinned here - they come from the
# gemspec development dependencies and always resolve to the latest release. These two
# appraisals exist to cover the one thing Idempo actually declares a runtime dependency
# on: Rack 2 versus Rack 3.
appraise "rack-2" do
  gem "rack", ">= 2.0", "< 3.0"
end

appraise "rack-3" do
  gem "rack", ">= 3.0"
end
