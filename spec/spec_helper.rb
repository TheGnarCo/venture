ENV["RAILS_ENV"] ||= "test"

require "venture"
require "rails/all"
require "spec_helper"
require "rspec/rails"
require "pry"

require_relative "support/logger"
require_relative "support/events"
require_relative "support/errors"
require_relative "support/widget"


ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|
  config.use_transactional_fixtures = true
end

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
