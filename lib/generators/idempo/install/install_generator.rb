# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

# Note this is `class Idempo` and not `module Idempo` - Idempo is a class, and reopening
# it as a module raises a TypeError once lib/idempo.rb has been loaded
class Idempo
  module Generators
    # Generates the migration for the Idempo tables. Existing installations already have
    # `idempo_responses` from an earlier version of Idempo and only need `idempo_locks`,
    # so the generator detects which of the two situations it is in.
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Creates a migration for the Idempo tables (idempo_responses and idempo_locks)"

      class_option :locks_only, type: :boolean, default: nil,
        desc: "Only create idempo_locks (default: detect whether idempo_responses already exists)"

      def create_migration_file
        say_status :idempo, migration_explanation
        migration_template "install_migration.rb.tt", File.join(db_migrate_path, "#{migration_name}.rb")
      end

      private

      def migration_name
        locks_only? ? "add_idempo_locks" : "install_idempo"
      end

      def migration_class_name
        migration_name.camelize
      end

      def migration_explanation
        if !options[:locks_only].nil?
          locks_only? ? "creating idempo_locks only (--locks-only)" : "creating both Idempo tables (--no-locks-only)"
        elsif locks_only?
          "idempo_responses is already present, creating idempo_locks only"
        else
          "creating both Idempo tables"
        end
      end

      def locks_only?
        return options[:locks_only] unless options[:locks_only].nil?
        @locks_only = responses_table_already_present? if !defined?(@locks_only)
        @locks_only
      end

      # An existing installation may not have a database we can connect to at the moment
      # the generator runs (a fresh checkout, or a CI box), so fall back to looking at the
      # schema dump before assuming this is a fresh install.
      def responses_table_already_present?
        connection_says_responses_table_exists?
      rescue => e
        say_status :idempo, "could not query the database (#{e.class}), reading the schema dump instead", :yellow
        schema_dump_mentions_responses_table?
      end

      def connection_says_responses_table_exists?
        ActiveRecord::Base.connection.table_exists?("idempo_responses")
      end

      def schema_dump_mentions_responses_table?
        %w[db/schema.rb db/structure.sql].any? do |relative_path|
          path = File.expand_path(relative_path, destination_root)
          File.exist?(path) && File.read(path).include?("idempo_responses")
        end
      end

      def migration_version
        "[%d.%d]" % [ActiveRecord::VERSION::MAJOR, ActiveRecord::VERSION::MINOR]
      end
    end
  end
end
