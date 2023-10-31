# frozen_string_literal: true

require 'spec_helper'
require 'active_record'
require 'mysql2'
require_relative 'shared_backend_specs'

RSpec.describe Idempo::ActiveRecordBackend do
  let(:connection) do
    if ENV['CI']
      {host: ENV['MYSQL_HOST'], port: ENV['MYSQL_PORT'], adapter: 'mysql2'}
    else
      {adapter: 'mysql2'}
    end
  end

  before :all do
    seed_db_name = Random.new(RSpec.configuration.seed).hex(4)
    ActiveRecord::Base.establish_connection(**connection, username: 'root')
    ActiveRecord::Base.connection.create_database('idempo_tests_%s' % seed_db_name, charset: :utf8mb4)
    ActiveRecord::Base.connection.close
    ActiveRecord::Base.establish_connection(**connection, encoding: 'utf8mb4', charset: 'utf8mb4', collation: 'utf8mb4_unicode_ci', username: 'root', database: 'idempo_tests_%s' % seed_db_name)

    ActiveRecord::Schema.define(version: 1) do |via_definer|
      Idempo::ActiveRecordBackend.create_table(via_definer)
    end
  end

  after :all do
    seed_db_name = Random.new(RSpec.configuration.seed).hex(4)
    ActiveRecord::Base.connection.drop_database('idempo_tests_%s' % seed_db_name)
  end

  let(:subject) do
    described_class.new
  end

  it_should_behave_like "a backend for Idempo"
end
