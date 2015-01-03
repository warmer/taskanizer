require File.join(File.dirname(__FILE__), 'fintrack/fintrack.rb')

map '/finances' do
  run Fintrack
end
