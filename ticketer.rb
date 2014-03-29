
class Ticketer
  def initialize()
  end
  
  
  
end

class Command
  COMMANDS = [:list, :pri, :mine, :own, :unassigned, :return, :add]
  USAGE = {
    :list => "[priority [assignee]]\n\tDefaults to all priorities, current user"
    :pri => "[]\n\t"
  }
  
  @command = nil
  @user = nil
  @args = nil
  @root_path = File.expand_path( '~/tickets/tickets' )
  
  def initialize(options = {})
    # find out what we're supposed to do
    raise_help unless options[:cmd]
    if options[:cmd]
      COMMANDS.each {|c| if c == options[:cmd].to_sym; @command = c; break; end }
    end
    raise_help "Could not understand command: #{options[:cmd]}" unless cmd
    
    @user = options[:user] || "unassigned"
    
    @args = options[:args] || []
    
    #parse any other arguments
  end
  
  def self.raise_help(msg == nil)
    
  end
  
  def execute
    case @command
      when :list
        pri = @args[0]
        assignee = @args[1] || @user
        
        
      else
        raise "Command unimplemented: #{@command}"
    end
    
    
  end
  
end

# has this been invoked directly?
if __FILE__ == $0
  Command.raise_help unless ARGV.length > 0
  
  opts = YAML.load_file( File.expand_path('~/.tickets') )
  
  opts[:cmd] => ARGV[0]
  ARGV.delete_at(0)
  
  opts[:args] => ARGV
  
  command = Command.new(opts)
  
  command.execute
end