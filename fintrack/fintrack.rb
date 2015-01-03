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

class Fintrack < Sinatra::Base

  def default_locals(overrides = {})
    locals = {
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
    location = escape(location)
    result = execute_query "SELECT Id FROM #{LOCATION_TABLE} WHERE location='#{location}';"
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

  get '/ajax/expenses/add' do
    vals = ['20140103000000', 1803, "This was a trip to 'Publix'"]
    res = insert(EXPENSE_TABLE, %w(Date Amount Notes), vals)
    res.to_s
  end

  get '/ajax/expenses' do
    start_date = params['start_date'] || beginning_of_month
    end_date = params['end_date'] || end_of_month

    expenses = []
    result = execute_query <<-SQL
      SELECT
        Id, Date, Amount, Location, Spender, Entered, Updated, Notes
      FROM #{EXPENSE_TABLE}
      WHERE Date >= #{start_date} and Date <= #{end_date}
      ORDER BY Date ASC;
    SQL

    expenses = result.map do |res|
      {
        'id' => res.shift,
        'date' => res.shift,
        'amount' => res.shift,
        'location' => res.shift,
        'spender' => res.shift,
        'entered' => res.shift,
        'updated' => res.shift,
        'notes' => res.shift,
      }
    end

    expenses.to_json
  end

  get '/ajax/dbdate' do
    date = execute_query "SELECT date('now');"
    date.to_json
  end


  #
  # POST
  #

  post '/expense' do
    date = params['date']
    amount = (params['amount'].to_f * 100).to_i
    location = params['location']
    tags = params['tags']
    notes = params['notes']
    entered = current_datetime
    updated = current_datetime

  end


  #
  # GET
  #

  get '/ping' do
    'pong!'
  end

  get '/manage/locations' do
    locals = default_locals

    erb :manage_locations, :locals => locals
  end

  get '/tickets' do
    tickets = $tickets.select{|t| true}
    params.each do |key, value|
      tickets = where(key, value, tickets)
    end

    grouped = group_by("location", tickets)

    locals = default_locals(
      :foo => "bar",
      :crumb_root => '/tickets',
      :grouped_tickets => grouped,
      :query_string => request.query_string,
      :crumbs => params,
    )

    erb :all_tickets, :locals => locals
  end

  get '/ticket/:id' do |id|
    num = id.to_i
    num = nil if num.to_s != id

    puts "### PARAMS: #{params}"

    confirm = false
    message = nil

    if params['status'] and num
      if params['confirmed'] == 'true'
        $tickets[num]['status'] = params['status']
        save_yaml($tickets, TASK_YAML)
        params.delete('status')
        params.delete('confirmed')
      else
        confirm = true
      end
    end

    locals = default_locals(
      :foo => "bar",
      :ticket_num => num,
      :ticket => (num ? $tickets[num] : nil),
      :new_status => params['status'],
      :confirm => confirm,
    )

    erb :ticket, :locals => locals
  end

  post '/set/location/:name/attribute/:att/:val' do |name, att, val|
    affected_area = nil

    $areas.each do |area|
      if area["name"] == name
        area[att] = val
        affected_area = area
      end
    end

    save_yaml($areas, LOCATION_YAML)

    affected_area.to_json || ""
  end

  post '/set/ticket/:id/attribute/:att/:val?' do |id, att, val|
    ticket_num = id.to_i
    return "" unless ticket_num.to_s == id
    affected_ticket = $tickets[ticket_num]

    if affected_ticket
      affected_ticket[att] = val
      save_yaml($tickets, TASK_YAML)
    end

    affected_ticket.to_json || ""
  end

  post '/set/ticket/:id/attribute/:att' do |id, att|
    ticket_num = id.to_i
    return "" unless ticket_num.to_s == id

    puts "### PARAMS: #{params}"

    affected_ticket = $tickets[ticket_num]

    if affected_ticket
      affected_ticket[att] = params["data"]
      save_yaml($tickets, TASK_YAML)
    end

    puts "### Resulting ticket: #{affected_ticket.to_json}"

    affected_ticket.to_json || ""
  end
end
