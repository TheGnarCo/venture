require 'active_record'
require 'venture'

require_relative 'support/logger'
require_relative 'support/events'
require_relative 'support/errors'
require_relative 'support/widget'

Venture.configure do |config|
  config.logger = Venture::Spec::Logger
end

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
Venture::Events::CreateEvents.new.migrate(:up)
Venture::Spec::CreateWidgets.new.migrate(:up)

Event = Venture::Events::Event
Widget = Venture::Spec::Widget
TestOkEvent = Venture::Spec::Events::TestOkEvent
TestOkEvent2 = Venture::Spec::Events::TestOkEvent2
TestFailureEvent = Venture::Spec::Events::TestFailureEvent
TestEventError = Venture::Spec::Errors::TestEventError

def clear_db
  [Event, Widget].each { |klass| klass.delete_all }
end
