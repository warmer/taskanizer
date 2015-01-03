require File.join(File.dirname(__FILE__), 'fintrack.rb')

map '/' do
  run Fintrack
end
