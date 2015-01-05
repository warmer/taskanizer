#!/usr/bin/env ruby

#
# This was NOT designed to protect against malicious requests.
#
# No warranty, express or implied, whatsoever.
#

require_relative 'common.rb'

def create_db
  exception = nil

  begin
    db = SQLite3::Database.open DATABASE_FILE

    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS #{LOCATION_TABLE}(
        Id INTEGER PRIMARY KEY,
        Name VARCHAR(255));
    SQL

    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS #{SPENDER_TABLE}(
        Id INTEGER PRIMARY KEY,
        Name VARCHAR(255));
    SQL

    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS #{TAG_TABLE}(
        Id INTEGER PRIMARY KEY,
        Name VARCHAR(255));
    SQL

    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS #{EXPENSE_TABLE}(
        Id INTEGER PRIMARY KEY,
        Date DATE,
        Amount INT,
        Location INTEGER,
        Spender INTEGER,
        Entered INTEGER DEFAULT CURRENT_TIMESTAMP,
        Updated INTEGER DEFAULT CURRENT_TIMESTAMP,
        Notes TEXT);
    SQL

    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS #{BUDGET_TABLE}(
        Id INTEGER PRIMARY KEY,
        PeriodDays INT,
        StartDate DATE,
        EndDate DATE,
        Created DATE,
        Updated DATE,
        Tag INT,
        Amount INT,
        Name VARCHAR(255));
    SQL

    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS #{EXPENSE_TAG_TABLE}(
        Id INTEGER PRIMARY KEY,
        Tag INT,
        Expense INT);
    SQL
  rescue SQLite3::Exception => e
    puts 'SQLite Exception'
    puts e
    exception = e
  ensure
    db.close if db
  end

  raise exception if exception
end


if __FILE__ == $0
  puts 'Creating the database...'
  create_db
  puts 'Database created!'
end
