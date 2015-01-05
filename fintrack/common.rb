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

DATE_FORMAT = '%Y%m%d'
TIME_FORMAT = '%H%M%S'

MAX_DATE = '99991231235959'
MIN_DATE = '00000101000000'

def date_ui2db(date)
  date.gsub('-', '') + '000000'
end

def date_db2ui(date)
  "#{date[0...4]}-#{date[4...6]}-#{date[6...8]}"
end

def amount_ui2db(amount)
  (amount.to_f * 100).round.to_i
end

def amount_db2ui(amount)
  sprintf('%0.2f', amount.to_f / 100.0)
end

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

def validate(columns, values)
  raise 'columns not an array' unless columns.is_a? Array
  raise 'values not an array' unless values.is_a? Array
  raise 'column count not equal to value count' unless columns.size == values.size

end

def update(table, columns, values, id)
  result = nil

  validate(columns, values)

  cols = columns.map {|c| "'#{c}'=?"}.join(', ')

  begin
    db = SQLite3::Database.open DATABASE_FILE

    prep = "update #{table} set #{cols} where Id=#{id};"
    puts "Prepared: #{prep}"

    statement = db.prepare prep
    statement.execute(values)
    statement.close
    result = id
  rescue SQLite3::Exception => e
    puts 'SQLite Exception'
    puts e
    exception = e
  rescue => e
    puts 'Generic exception:'
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

  validate(columns, values)

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
