# frozen_string_literal: true

require 'active_record'
require 'mysql2'
require 'spec_helper'
require_relative 'shared_backend_specs'

RSpec.describe Idempo::ActiveRecordBackend do
  before :all do
    seed_db_name = Random.new(RSpec.configuration.seed).hex(4)
    ActiveRecord::Base.establish_connection(adapter: 'postgresql', database: 'postgres')
    ActiveRecord::Base.connection.create_database('idempo_tests_%s' % seed_db_name, charset: :unicode)
    ActiveRecord::Base.connection.close
    ActiveRecord::Base.establish_connection(adapter: 'postgresql', encoding: 'unicode', database: 'idempo_tests_%s' % seed_db_name)

    ActiveRecord::Schema.define(version: 1) do |via_definer|
      Idempo::ActiveRecordBackend.create_table(via_definer)
    end
  end

  after :all do
    seed_db_name = Random.new(RSpec.configuration.seed).hex(4)
    ActiveRecord::Base.connection.close
    ActiveRecord::Base.establish_connection(adapter: 'postgresql', database: 'postgres')
    ActiveRecord::Base.connection.drop_database('idempo_tests_%s' % seed_db_name)
  end

  let(:subject) do
    described_class.new
  end

  it_should_behave_like "a backend for Idempo"
end
