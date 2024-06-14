class Venture::Events::Event < ActiveRecord::Base
  self.table_name_prefix = Venture::Config.table_name_prefix
  validates_presence_of :type
end

# for convenience:
Venture::Event = Venture::Events::Event
