#!/usr/bin/env ruby

#
# This was NOT designed to protect against malicious requests.
#
# No warranty, express or implied, whatsoever.
#

require 'sinatra'
require 'json'
require 'pp'
require 'sqlite3'

require_relative 'common.rb'

PATH_ROOT = '/'

LOCATION_FILTER_REGEX = /[^a-zA-Z0-9\/,'\. #\$\*_\+!]/
# do not allow commas in tags since we split on commas
TAG_FILTER_REGEX = /[^a-zA-Z0-9\/'\. #\$\*_\+!]/

URL = {
  'expenses' => PATH_ROOT + 'expenses',
  'expense_add' => PATH_ROOT + 'expense/add',
  'expense_delete' => PATH_ROOT + 'expense/delete/:id',
  'expense_edit' => PATH_ROOT + 'expense/edit/:id',

  'budget' => PATH_ROOT + 'budget',
  'budget_add' => PATH_ROOT + 'budget/add',
  'budget_delete' => PATH_ROOT + 'budget/delete/:id',
  'budget_edit' => PATH_ROOT + 'budget/edit/:id',

  'tag' => PATH_ROOT + 'tag/:id',
}

class Fintrack < Sinatra::Base

  def agg_locals(overrides = {})
    locals = {
      # TODO: sinatra might have a mechanism for creating route-aware URLs...
      'url' => URL,
    }

    locals.merge(overrides)
  end

  def beginning_of_month
    Date.civil(Date.today.year, Date.today.month, 1).strftime("#{DATE_FORMAT}000000")
  end

  def end_of_month
    Date.civil(Date.today.year, Date.today.month, -1).strftime("#{DATE_FORMAT}235959")
  end

  def current_datetime
    DateTime.now.strftime("#{DATE_FORMAT}#{TIME_FORMAT}")
  end

  def date_today
    DateTime.now.strftime('%Y-%m-%d')
  end

  def location_id(location)
    puts "Location starting with #{location}"
    location = location.strip.gsub(/(['])/, '\'\1')
    puts "Location now #{location}"
    location = location.gsub(LOCATION_FILTER_REGEX, '')
    puts "Location finally #{location}"
    result = execute_query "SELECT Id FROM #{LOCATION_TABLE} WHERE Name LIKE '#{location}';"

    if result.size == 1
      id = result.flatten[0]
    elsif result.size == 0
      vals = [location.gsub("''", "'")]
      id = insert(LOCATION_TABLE, %w(Name), vals)
    end

    id
  end

  def tag_id(tag, add_if_not_exist = true)
    id = nil
    tag = tag.strip.gsub(/(['])/, '\'\1')
    tag = tag.gsub(TAG_FILTER_REGEX, '')
    result = execute_query "SELECT Id FROM #{TAG_TABLE} WHERE Name LIKE '#{tag}';"

    if result.size == 1
      id = result.flatten[0]
    elsif result.size == 0 and add_if_not_exist
      vals = [tag.gsub("''", "'")]
      id = insert(TAG_TABLE, %w(Name), vals)
    end

    id
  end

  def locations
    result = execute_query "SELECT Name FROM #{LOCATION_TABLE};"
    result.flatten
  end

  def tags
    result = execute_query "SELECT Name FROM #{TAG_TABLE};"
    result.flatten
  end

  def tags_for_expense(id)
    result = execute_query <<-SQL
      SELECT t.Id, t.Name FROM
        #{EXPENSE_TAG_TABLE} as et, #{TAG_TABLE} as t
      WHERE
        et.Expense=#{id} AND et.Tag=t.Id;
    SQL

    result = result.map do |tag|
      { 'id' => tag[0], 'name' => tag[1] }
    end

    result
  end

  def location_for(id)
    result = execute_query "SELECT Name FROM #{LOCATION_TABLE} WHERE Id=#{id};"
    result.flatten[0]
  end

  def tag_for(id)
    result = execute_query "SELECT Name FROM #{TAG_TABLE} WHERE Id=#{id};"
    result.flatten[0]
  end

  def expenses(opts = {})
    start_date = opts['start_date'] || beginning_of_month
    end_date = opts['end_date'] || end_of_month
    ids = opts['ids']

    result = execute_query <<-SQL
      SELECT
        Id, Date, Amount, Location, Spender, Entered, Updated, Notes
      FROM #{EXPENSE_TABLE}
      WHERE Date >= #{start_date} and Date <= #{end_date}
        #{ids ? "and Id IN (#{ids.join(',')})" : ''}
      ORDER BY Date ASC;
    SQL

    result.map do |res|
      id = res[0]
      map = {
        'id' => res.shift,
        'date' => res.shift.to_s,
        'amount' => res.shift,
        'location' => location_for(res.shift),
        'spender' => res.shift,
        'entered' => res.shift,
        'updated' => res.shift,
        'notes' => res.shift || '',
        'tags' => tags_for_expense(id) || [],
      }

      map['date'] = "#{map['date'][0...4]}-#{map['date'][4...6]}-#{map['date'][6...8]}"
      map['amount'] = sprintf("%0.2f", map['amount'].to_f / 100.0)

      map
    end
  end

  def budgets(opts = {})
    end_date_after = opts['end_date_after'] || beginning_of_month
    start_date_before = opts['start_date_before'] || end_of_month
    ids = opts['ids']
    tag_id = opts['tag_id']

    result = execute_query <<-SQL
      SELECT
        Id, Tag, PeriodDays, StartDate, EndDate, Created, Updated, Amount, Name
      FROM #{BUDGET_TABLE}
      WHERE
        StartDate <= #{start_date_before} AND EndDate >= #{end_date_after}
        #{ids ? "AND Id IN (#{ids.join(',')})" : ''}
        #{tag_id ? "AND Tag=#{tag_id}" : ''}
      ORDER BY Amount DESC;
    SQL

    result.map do |res|
      id = res[0]
      map = {
        'id' => res.shift,
        'tag' => res.shift,
        'period' => res.shift,
        'start_date' => res.shift.to_s,
        'end_date' => res.shift.to_s,
        'entered' => res.shift,
        'updated' => res.shift,
        'amount' => res.shift,
        'name' => res.shift,
      }

      %w(start_date end_date).each do |key|
        map[key] = date_db2ui(map[key])
      end

      map['amount'] = amount_db2ui(map['amount'])
      if map['tag']
        map['tag'] = {
          'id' => map['tag'],
          'name' => tag_for(map['tag']),
        }
      end

      map
    end
  end

  def budget_with_tag(id)
    budgets('start_date' => MIN_DATE, 'end_date' => MAX_DATE, 'tag_id' => id)[0]
  end

  def expenses_with_tag(id)
    eids = execute_query("SELECT Expense FROM ExpenseTags WHERE Tag=#{id};").flatten
    expenses('start_date' => MIN_DATE, 'end_date' => MAX_DATE, 'ids' => eids)
  end

  def expense_for(id)
    expenses('start_date' => MIN_DATE, 'end_date' => MAX_DATE, 'ids' => [id])[0]
  end

  def budget_for(id)
    budgets('end_date_after' => MIN_DATE, 'start_date_before' => MAX_DATE, 'ids' => [id])[0]
  end

  #
  # Handlers for page requests
  #

  #
  # AJAX
  #
  # Ajax calls always return JSON objects
  #

  get '/ajax/tags' do
    tags = {}
    result = execute_query "SELECT Id, Name FROM #{TAG_TABLE}"

    result.each do |res|
      tags[res[0]] = res[1]
    end

    tags.to_json
  end

  get '/ajax/spenders' do
    spenders = {}
    result = execute_query "SELECT Id, Name FROM #{SPENDER_TABLE}"

    result.each do |res|
      spenders[res[0]] = res[1]
    end

    spenders.to_json
  end

  get '/ajax/locations' do
    locations = {}
    result = execute_query "SELECT Id, Name FROM #{LOCATION_TABLE}"

    result.each do |res|
      locations[res[0]] = res[1]
    end

    locations.to_json
  end

  get '/ajax/tag_id/:tag' do |tag|
    tag_id(tag).to_s
  end

  get '/ajax/location_id/:location' do |location|
    location_id(location).to_s
  end

  get '/ajax/expenses' do
    expenses(params).to_json
  end

  get '/ajax/expense/:id' do |id|
    expense_for(id).to_json
  end

  #
  # GET/POST Helpers (to reduce code duplication)
  #

  def expense_edit(params = {})
    id = (params['id'] || '0').to_i
    date = date_ui2db(params['date'])
    amount = amount_ui2db(params['amount'])
    location = params['location']
    tags = params['tags'].split(',')
    notes = params['notes']
    entered = current_datetime
    updated = current_datetime
    edited = params['edited']

    if id > 0
      if params['confirm_delete']
        res = execute_query("DELETE FROM #{EXPENSE_TABLE} WHERE Id=#{id};")
        res = execute_query("DELETE FROM #{EXPENSE_TAG_TABLE} WHERE Expense=#{id};")
        id = 0
      else
        loc_id = location_id(location)

        vals = [id, date, amount, loc_id, notes, updated]
        id = update(EXPENSE_TABLE, %w(Id Date Amount Location Notes Updated), vals, id)
      end
    else
      loc_id = location_id(location)

      vals = [date, amount, loc_id, notes, entered, updated]
      id = insert(EXPENSE_TABLE, %w(Date Amount Location Notes Entered Updated), vals)
    end

    if id > 0
      # delete all current tag associations
      execute_query("DELETE FROM #{EXPENSE_TAG_TABLE} WHERE Expense=#{id};")

      tags = tags.reject {|tag| tag.strip.length == 0}
      tag_ids = tags.map do |tag|
        tag_id(tag)
      end
      tag_ids.reject! {|i| !i || i <= 0}

      # apply new associations
      tag_ids.each do |tag_id|
        insert(EXPENSE_TAG_TABLE, %w(Tag Expense), [tag_id, id])
      end
    end

    if edited
      if id > 0
        redirect to("#{PATH_ROOT}expense/edit/#{id}?updated=true")
      else
        #deleted
        redirect to(PATH_ROOT + 'expenses?expense_deleted=true')
      end
    else
      redirect to(PATH_ROOT)
        redirect to(PATH_ROOT + 'expenses?expense_added=true')
    end
  end

  def budget_update(budget)
    # convert fields to be database-friendly
    id = budget['id']
    period = budget['period']
    start_date = date_ui2db(budget['start_date'])
    end_date = date_ui2db(budget['end_date'])
    updated = current_datetime
    name = budget['name']
    amount = amount_ui2db(budget['amount'])
    tag = budget['tag']
    tag = tag_id(tag) if tag != ''

    if id > 0
      vals = [id, period, start_date, end_date, updated, name, amount, tag]
      id = update(BUDGET_TABLE, %w(Id PeriodDays StartDate EndDate Updated Name Amount Tag), vals, id)
    else
      created = current_datetime
      vals = [period, start_date, end_date, created, updated, name, amount, tag]
      id = insert(BUDGET_TABLE, %w(PeriodDays StartDate EndDate Created Updated Name Amount Tag), vals)
    end

    if id > 0
      redirect to("#{PATH_ROOT}budget/edit/#{id}?updated=true")
    end
  end

  def budget_edit(params = {})
    id = (params['id'] || 0).to_i
    puts "Given a budget: #{id.inspect}" if id
    bom = beginning_of_month
    lm = MAX_DATE

    period_days = (params['period_days'] || 30).to_i
    start_date = params['start_date'] || "#{bom[0...4]}-#{bom[4...6]}-#{bom[6...8]}"
    end_date = params['end_date'] || "#{lm[0...4]}-#{lm[4...6]}-#{lm[6...8]}"
    #end_date = params['end_date'] ? params['end_date'].gsub('-', '') : beginning_of_month
    name = params['name'] || ''
    amount = params['amount'] || '0.00'
    tag = params['tag'] || ''

    budget = {
      'id' => id,
      'period_days' => period_days,
      'start_date' => start_date,
      'end_date' => end_date,
      'name' => name,
      'amount' => amount,
      'tag' => tag,
    }

    # TODO: delete budget?
    if params['confirm_delete'] and id > 0
      execute_query("DELETE FROM #{BUDGET_TABLE} WHERE Id=#{id};")
      redirect to(URL['budget'])
    elsif params['do_update']
      budget_update(budget)
    else
      page_vars = {
        'budget' => budget,
      }

      erb :budget_edit, :locals => agg_locals(page_vars)
    end
  end

  #
  # POST
  #

  post URL['expense_add'] do
    expense_edit(params)
  end

  post URL['expense_edit'] do
    expense_edit(params)
  end

  post URL['budget_add'] do
    budget_edit(params)
  end

  post URL['budget_edit'] do |id|
    budget_edit(params)
  end

  post URL['tag'] do |tag_id|
    id = tag_id.to_i
    if tag_id == id.to_s and id > 0
      name = params['name'].gsub(TAG_FILTER_REGEX, '')
      # see if any other tags have this name, but don't create a new tag
      existing_id = tag_id(name, false)
      if existing_id and existing_id != id
        redirect_to(URL['tag'].gsub(':id', id.to_s) + '?name_collision=true')
      else
        # change the tag name
        id = update(TAG_TABLE, %w(Name), [name], id)
        # redirect
        redirect to(URL['tag'].gsub(':id', id.to_s) + '?updated=true')
      end
    else
      puts "id: #{id}; tag_id: #{tag_id}"
      redirect to(URL['expenses'] + '?invalid_tag_id=true')
    end
  end

  #
  # GET
  #

  get '/ping' do
    'pong!'
  end

  get '/' do
      redirect to(URL['expenses'])
  end

  get URL['expenses'] do
    messages = []
    messages << {'level' => 'success', 'body' => 'Expense has been added'} if params['expense_added']
    messages << {'level' => 'info', 'body' => 'Expense has been added'} if params['expense_deleted']
    messages << {'level' => 'warning', 'body' => 'Invalid ID given for tag'} if params['invalid_tag_id']
    page_vars = {
      'visible_expenses' => expenses(params),
      'today' => date_today,
      'messages' => messages,
    }

    erb :expenses, :locals => agg_locals(page_vars)
  end

  get URL['expense_edit'] do |id|
    messages = []
    messages << {'level' => 'success', 'body' => 'Expense has been upated'} if params['updated']
    page_vars = {
      'expense' => expense_for(id),
      'messages' => messages,
    }

    erb :expense_edit, :locals => agg_locals(page_vars)
  end

  get URL['budget'] do
    page_vars = {
      'visible_budgets' => budgets,
    }

    erb :budgets, :locals => agg_locals(page_vars)
  end

  get URL['budget_add'] do
    budget_edit
  end

  get URL['budget_edit'] do |id|
    budget = budget_for(id)

    budget_edit(budget.merge(params))
  end

  get URL['tag'] do |id|
    tag_name = tag_for(id)
    budget = budget_with_tag(id)
    expenses = expenses_with_tag(id)

    puts "Budget for #{tag_name}: #{budget}"
    puts "Expenses for #{tag_name}: #{expenses}"

    messages = []
    messages << {'level' => 'success', 'body' => 'Tag updated'} if params['updated']
    page_vars = {
      'tag' => {'id' => id, 'name' => tag_name},
      'visible_budgets' => budget ? [budget] : [],
      'visible_expenses' => expenses,
      'messages' => messages,
    }

    erb :tag, :locals => agg_locals(page_vars)
  end

end
