module Venture::Events
  class Venture::Events::Event < ActiveRecord::Base
    self.table_name_prefix = Venture::Config.table_name_prefix
    validates_presence_of :type
  end

  class CreateEvents < ActiveRecord::Migration[5.0]
    def change
      create_table Venture::Events::Event.table_name do |t|
        t.send(Venture.event_data_column_type, :data)
        t.string :type, null: false
        t.timestamps
      end
    end
  end
end

# save some typing:
Venture::Event = Venture::Events::Event
