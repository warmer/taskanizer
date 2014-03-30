#
# This was NOT designed to protect against malicious requests.
#
# No warranty, express or implied, whatsoever.
#

require 'sinatra'
require 'yaml'
require 'json'
require 'pp'

TASK_YAML = 'all_tasks.yml'
LOCATION_YAML = 'areas.yml'

$tickets = []
$areas = []
$time_options = [
  "15 minutes",
  "1 hour",
  "3 hours",
  "all day",
  "2+ days",
]
$levels = ["Garage", "Main", "Second", "Third"]
$owners = ["Kenneth", "Tatyana", "Both"]

def default_locals(overrides = {})
  locals = {
    :query_string => '',
    :crumbs => {},
    :areas => $areas,
    :grouped_areas => group_by("level", $areas),
    :tickets => $tickets,
    :grouped_tickets => group_by("location", $tickets),
    :levels => $levels,
    :time_options => $time_options,
    :owners => $owners,
  }
  
  locals.merge(overrides)
end

def save_yaml(ticket_list, dest)
  puts "saving YAML"
  File.open(dest, 'w') {|f| f.write(ticket_list.to_yaml)}
end

def groups_of(key, ticket_list)
  groups = []
  
  ticket_list.each do |ticket|
    if not groups.include?(ticket[key])
      groups << ticket[key]
    end
  end
  
  groups.map{|g| {"name" => g} }
end

def group_by(key, map_array)
  grouped = {}
  
  map_array.each do |ticket|
    if not grouped.has_key?(ticket[key])
      grouped[ticket[key]] = []
    end
    grouped[ticket[key]] << ticket
  end
  
  grouped
end

def where(key, value, ticket_list)
  if value == "" || value == nil
    ticket_list.select {|t| t[key] == nil || t[key] == "" }
  else
    ticket_list.select {|t| t[key] == value}
  end
end

#TEST DEBUG
if not File.exists?(TASK_YAML)
  id = 0
  File.open('task_list.tsv').each do |line|
    ticket = line.split("\t");
    $tickets << {
      "location" => ticket[0],
      "item" => ticket[1],
      "owner" => nil,
      "id" => id
    }
    id += 1
  end
  
  $areas = groups_of("location", $tickets)
  
  save_yaml($tickets, TASK_YAML)
  save_yaml($areas, LOCATION_YAML)
else
  puts "Loading existing file: #{TASK_YAML}"
  $tickets = YAML.load(File.open(TASK_YAML))
  $areas = YAML.load(File.open(LOCATION_YAML))
end

puts "Loaded #{$tickets.count} tickets"
#TEST DEBUG


#
# Handlers for page requests
#

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