#
# This was NOT designed to protect against malicious requests.
#
# No warranty, express or implied, whatsoever.
#

require 'sqlite3'

DATABASE_FILE = 'db/fintrack.db'

TAG_TABLE = 'Tags'
SPENDER_TABLE = 'Spenders'
EXPENSE_TABLE = 'Expenses'
LOCATION_TABLE = 'Locations'
BUDGET_TABLE = 'Budgets'
EXPENSE_TAG_TABLE = 'ExpenseTags'
BUDGET_TAG_TABLE = 'BudgetTags'

DATE_FORMAT = '%Y%m%d'
TIME_FORMAT = '%H%M%S'

def execute_query(query)
  result = nil

  begin
    db = SQLite3::Database.open DATABASE_FILE

    puts "Executing: #{query}"
    result = db.execute query
  rescue SQLite3::Exception => e
    puts 'SQLite Exception'
    puts e
    exception = e
  ensure
    db.close if db
  end

  raise exception if exception

  result
end

def insert(table, columns, values)
  result = nil

  raise 'columns not an array' unless columns.is_a? Array
  raise 'values not an array' unless values.is_a? Array
  raise 'column count not equal to value count' unless columns.size == values.size

  cols = columns.map {|c| "'#{c}'"}.join(',')
  val_args = (['?'] * columns.size).join(',')

  begin
    db = SQLite3::Database.open DATABASE_FILE

    prep = "insert into #{table} (#{cols}) values (#{val_args});"
    puts "Prepared: #{prep}"

    ins = db.prepare prep

    puts "Inserting: #{values}"
    ins.execute(values)
    ins.close
    result = db.last_insert_row_id
    puts "Insert result: #{result}"
  rescue SQLite3::Exception => e
    puts 'SQLite Exception'
    puts e
    exception = e
  ensure
    db.close if db
  end

  raise exception if exception

  result
end
