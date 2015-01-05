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

LOCATION_FILTER_REGEX = /[^a-zA-Z0-9\/,\. #\$\*_\+!]/
# do not allow commas in tags since we split on commas
TAG_FILTER_REGEX = /[^a-zA-Z0-9\/\. #\$\*_\+!]/

class Fintrack < Sinatra::Base

  def agg_locals(overrides = {})
    locals = {
      'url' => {
        'home' => PATH_ROOT,
        'expense_post' => PATH_ROOT + 'expense',
        'expense_delete' => PATH_ROOT + 'expense/delete/%id%',
        'expense_edit' => PATH_ROOT + 'expense/edit/%id%',
        'expense_update' => PATH_ROOT + 'expense/update',

        'budget_delete' => PATH_ROOT + 'budget/delete/%id%',
        'budget_post' => PATH_ROOT + 'budget',
        'budget_edit' => PATH_ROOT + 'budget/edit/%id%',
        'budget_update' => PATH_ROOT + 'budget/update',
      }
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

  def location_id(location)
    puts "Location starting with #{location}"
    location = location.strip.gsub(/(['])/, '\'\1')
    puts "Location now #{location}"
    location = location.gsub(LOCATION_FILTER_REGEX, '')
    puts "Location finally #{location}"
    result = execute_query "SELECT Id FROM #{LOCATION_TABLE} WHERE Name='#{location}';"

    if result.size == 1
      id = result.flatten[0]
    elsif result.size == 0
      vals = [location.gsub("''", "'")]
      id = insert(LOCATION_TABLE, %w(Name), vals)
    end

    id
  end

  def tag_id(tag)
    id = nil
    tag = tag.strip.gsub(/(['])/, '\'\1')
    tag = tag.gsub(TAG_FILTER_REGEX, '')
    result = execute_query "SELECT Id FROM #{TAG_TABLE} WHERE Name='#{tag.downcase}';"

    if result.size == 1
      id = result.flatten[0]
    elsif result.size == 0
      vals = [tag]
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
      SELECT t.Name FROM
        #{EXPENSE_TAG_TABLE} as et, #{TAG_TABLE} as t
      WHERE
        et.Expense=#{id} AND et.Tag=t.Id;
    SQL

    result.flatten
  end

  def location_for(id)
    result = execute_query "SELECT Name FROM #{LOCATION_TABLE} WHERE Id=#{id};"
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

  def expense_for(id)
    expenses('start_date' => MIN_DATE, 'end_date' => MAX_DATE, 'ids' => [id])[0]
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

  def budget_edit(params = {})
    bom = beginning_of_month
    lm = MAX_DATE

    period_days = params['period_days'] || '30'
    start_date = params['start_date'] || "#{bom[0...4]}-#{bom[4...6]}-#{bom[6...8]}"
    end_date = params['end_date'] || "#{lm[0...4]}-#{lm[4...6]}-#{lm[6...8]}"
    #end_date = params['end_date'] ? params['end_date'].gsub('-', '') : beginning_of_month
    name = params['name'] || ''
    amount = params['amount'] || '0.00'
    tag = params['tag'] || ''

    budget = {
      'period_days' => period_days,
      'start_date' => start_date,
      'end_date' => end_date,
      'name' => name,
      'amount' => amount,
      'tag' => tag,
    }

    page_vars = {
      'budget' => budget,
    }

    erb :budget_edit, :locals => agg_locals(page_vars)
  end

  #
  # POST
  #

  def expense_edit(params = {})
    id = (params['id'] || '0').to_i
    date = params['date'].gsub('-', '') + '000000'
    amount = (params['amount'].to_f * 100).round.to_i
    location = params['location']
    tags = params['tags'].split(',')
    notes = params['notes']
    entered = current_datetime
    updated = current_datetime

    loc_id = location_id(location)
    tags = tags.reject {|tag| tag.strip.length == 0}

    tag_ids = tags.map do |tag|
      tag_id(tag)
    end
    tag_ids.reject! {|i| !i || i <= 0}

    vals = [date, amount, loc_id, notes, entered, updated]

    res = insert(EXPENSE_TABLE, %w(Date Amount Location Notes Entered Updated), vals)

    if res > 0
      tag_ids.each do |tag_id|
        insert(EXPENSE_TAG_TABLE, %w(Tag Expense), [tag_id, res])
      end
    end

    puts "Added expense ID #{res}"

    puts "vals: #{vals}"
    puts "params: #{params.inspect}"

    redirect to(PATH_ROOT)
  end

  post '/expense' do
    expense_edit(params)
  end

  post '/expense/update' do
    id = params['id'].to_i
    date = params['date'].gsub('-', '') + '000000'
    amount = (params['amount'].to_f * 100).round.to_i
    location = params['location']
    tags = params['tags'].split(',')
    notes = params['notes']
    updated = current_datetime

    puts "params: #{params.inspect}"

    if id > 0 and !params['confirm_delete']
      loc_id = location_id(location)

      vals = [id, date, amount, loc_id, notes, updated]
      puts "vals: #{vals}"

      res = update(EXPENSE_TABLE, %w(Id Date Amount Location Notes Updated), vals, id)

      if res > 0
        # delete all current tag associations
        execute_query("DELETE FROM #{EXPENSE_TAG_TABLE} WHERE Expense=#{id.to_i};")

        tags = tags.reject {|tag| tag.strip.length == 0}
        tag_ids = tags.map do |tag|
          tag_id(tag)
        end
        tag_ids.reject! {|i| !i || i <= 0}

        # apply new associations
        tag_ids.each do |tag_id|
          insert(EXPENSE_TAG_TABLE, %w(Tag Expense), [tag_id, id])
        end

        puts "Added expense ID #{res}"
      end
      redirect to("#{PATH_ROOT}expense/edit/#{id}?updated=true")
    elsif id > 0 and params['confirm_delete']
      puts 'This should delete the item!'
      res = execute_query("DELETE FROM #{EXPENSE_TABLE} WHERE Id=#{id.to_i};")
      res = execute_query("DELETE FROM #{EXPENSE_TAG_TABLE} WHERE Expense=#{id.to_i};")
    end

    redirect to(PATH_ROOT)
  end


  #
  # GET
  #

  get '/ping' do
    'pong!'
  end

  get '/' do
    page_vars = {
      'visible_expenses' => expenses(params),
    }

    erb :expenses, :locals => agg_locals(page_vars)
  end

  get '/budget/add' do
    budget_edit
  end

  get '/expense/edit/:id' do |id|
    page_vars = {
      'expense' => expense_for(id),
      'updated' => params['updated'] || false,
    }

    erb :expense_edit, :locals => agg_locals(page_vars)
  end

  get '/expense/delete/:id' do |id|
    res = execute_query("DELETE FROM #{EXPENSE_TABLE} WHERE Id=#{id.to_i};")
    res = execute_query("DELETE FROM #{EXPENSE_TAG_TABLE} WHERE Expense=#{id.to_i};")

    redirect to(PATH_ROOT)
  end


end
