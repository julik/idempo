# frozen_string_literal: true

require "active_record"
require "mysql2"
require "spec_helper"
require_relative "shared_backend_specs"
require_relative "shared_token_lock_specs"

RSpec.describe Idempo::ActiveRecordBackend do
  before :all do
    seed_db_name = Random.new(RSpec.configuration.seed).hex(4)
    ActiveRecord::Base.establish_connection(adapter: "postgresql", database: "postgres")
    ActiveRecord::Base.connection.create_database("idempo_tests_%s" % seed_db_name, charset: :unicode)
    ActiveRecord::Base.connection.close
    ActiveRecord::Base.establish_connection(adapter: "postgresql", encoding: "unicode", database: "idempo_tests_%s" % seed_db_name)

    ActiveRecord::Schema.define(version: 1) do |via_definer|
      Idempo::ActiveRecordBackend.create_table(via_definer)
      Idempo::ActiveRecordBackend.create_locks_table(via_definer)
    end
  end

  after :all do
    seed_db_name = Random.new(RSpec.configuration.seed).hex(4)
    ActiveRecord::Base.connection.close
    ActiveRecord::Base.establish_connection(adapter: "postgresql", database: "postgres")
    ActiveRecord::Base.connection.drop_database("idempo_tests_%s" % seed_db_name)
  end

  let(:subject) do
    described_class.new
  end

  it_should_behave_like "a backend for Idempo"
  describe "the TokenLock" do
    it_should_behave_like "a TokenLock"

    # Behind PGBouncer several app hosts share one database, and their clocks need not agree
    it "uses the clock of the database, not the one of the process" do
      connection = ActiveRecord::Base.connection
      holder = described_class::TokenLock.new
      expect(holder.acquire(connection, "clock-key")).to eq(true)

      process_clock_ahead = Time.now + 3600
      allow(Time).to receive(:now).and_return(process_clock_ahead)

      expect(holder.held?(connection, "clock-key")).to eq(true)
      expect(described_class::TokenLock.new.acquire(connection, "clock-key")).to eq(false)
      subject.prune!
      expect(subject.lock_model.count).to eq(1)

      holder.release(connection, "clock-key")
    end
  end
end
