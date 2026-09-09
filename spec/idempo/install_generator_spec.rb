# frozen_string_literal: true

require "active_record"
require "sqlite3"
require "rails/generators"
require "fileutils"
require "tmpdir"
require "spec_helper"
require_relative "../../lib/generators/idempo/install/install_generator"

RSpec.describe Idempo::Generators::InstallGenerator do
  let(:destination) { Dir.mktmpdir("idempo-generator") }

  before :each do
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    ActiveRecord::Migration.verbose = false
    FileUtils.mkdir_p(File.join(destination, "db"))
  end

  after :each do
    FileUtils.rm_rf(destination)
    ActiveRecord::Base.connection_handler.clear_all_connections!
  end

  def generate(args = [])
    silence_stream { described_class.new(args, args, destination_root: destination).invoke_all }
    path = Dir.glob(File.join(destination, "db/migrate/*.rb")).fetch(0)
    [File.basename(path), File.read(path)]
  end

  def silence_stream
    original, $stdout = $stdout, StringIO.new
    yield
  ensure
    $stdout = original
  end

  def create_responses_table!
    ActiveRecord::Schema.define(version: 1) do |via_definer|
      Idempo::ActiveRecordBackend.create_responses_table(via_definer)
    end
  end

  it "creates both tables for a fresh installation" do
    name, body = generate
    expect(name).to end_with("install_idempo.rb")
    expect(body).to include("create_responses_table")
    expect(body).to include("create_locks_table")
  end

  it "creates only the locks table when idempo_responses already exists" do
    create_responses_table!

    name, body = generate
    expect(name).to end_with("add_idempo_locks.rb")
    expect(body).not_to include("create_responses_table")
    expect(body).to include("create_locks_table")
  end

  it "falls back to the schema dump when the database cannot be queried" do
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: "/nonexistent/idempo/x.sqlite3")
    File.write(File.join(destination, "db/schema.rb"), %(create_table "idempo_responses", force: :cascade do |t|))

    name, body = generate
    expect(name).to end_with("add_idempo_locks.rb")
    expect(body).not_to include("create_responses_table")
  end

  it "honours an explicit --locks-only" do
    _name, body = generate(["--locks-only"])
    expect(body).not_to include("create_responses_table")
    expect(body).to include("create_locks_table")
  end

  it "generates a migration which runs and rolls back without touching a pre-existing responses table" do
    # Exactly what an existing installation has committed in its repo already
    create_responses_table!

    _name, body = generate
    eval(body) # standard:disable Security/Eval - this is the migration we just generated
    migration = Object.const_get(:AddIdempoLocks).new

    migration.migrate(:up)
    expect(ActiveRecord::Base.connection.tables).to include("idempo_locks", "idempo_responses")

    migration.migrate(:down)
    tables = ActiveRecord::Base.connection.tables
    expect(tables).not_to include("idempo_locks")
    expect(tables).to include("idempo_responses")
  ensure
    Object.send(:remove_const, :AddIdempoLocks) if Object.const_defined?(:AddIdempoLocks)
  end
end
