# frozen_string_literal: true

require_relative "lib/idempo/version"

Gem::Specification.new do |spec|
  spec.name = "idempo"
  spec.version = Idempo::VERSION
  spec.authors = ["Julik Tarkhanov", "Pablo Crivella"]
  spec.email = ["me@julik.nl", "pablocrivella@gmail.com"]

  spec.summary = "Idempotency keys for all."
  spec.description = "Provides idempotency keys for Rack applications."
  spec.homepage = "https://github.com/julik/idempo"
  spec.license = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.4.0")

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "https://rubygems.org"
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/julik/idempo/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "msgpack"
  spec.add_dependency "measurometer", "~> 1.3"
  spec.add_dependency "rack", ">= 2.0"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "redis", "~> 4"
  spec.add_development_dependency "rack-test"
  spec.add_development_dependency "activerecord"
  spec.add_development_dependency "mysql2"
  spec.add_development_dependency "pg"
  spec.add_development_dependency "standard"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
end
