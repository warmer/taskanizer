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

class Fintrack < Sinatra::Base

  def agg_locals(overrides = {})
    locals = {
      'url' => {
        'home' => PATH_ROOT,
        'expense_post' => PATH_ROOT + 'expense',
        'expense_delete' => PATH_ROOT + 'expense/delete/%id%',
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
    location = location.gsub(/[^a-zA-Z0-9\/\\',\. #\$\*_\+!]/, '')
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
    tag = tag.gsub(/[^a-zA-Z0-9\/\\',\. #\$\*_\+!]/, '')
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

    result = execute_query <<-SQL
      SELECT
        Id, Date, Amount, Location, Spender, Entered, Updated, Notes
      FROM #{EXPENSE_TABLE}
      WHERE Date >= #{start_date} and Date <= #{end_date}
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
      map['amount'] = map['amount'].to_f / 100.0

      map
    end
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

  get '/ajax/expenses/add' do
    vals = ['20140103000000', 1803, "This was a trip to 'Publix'"]
    res = insert(EXPENSE_TABLE, %w(Date Amount Notes), vals)
    res.to_s
  end

  get '/ajax/expenses' do
    expenses(params).to_json
  end

  get '/ajax/dbdate' do
    date = execute_query "SELECT date('now');"
    date.to_json
  end


  #
  # POST
  #

  post '/expense' do
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

  get '/expense/delete/:id' do |id|
    res = execute_query("DELETE FROM #{EXPENSE_TABLE} WHERE Id=#{id.to_i};")
    res = execute_query("DELETE FROM #{EXPENSE_TAG_TABLE} WHERE Expense=#{id.to_i};")

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
end
