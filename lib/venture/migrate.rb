module Venture::Migrate
  class CreateEvents < ActiveRecord::Migration[5.0]
    def change
      create_table Venture::Event.table_name do |t|
        t.string :type
        t.timestamps
      end
    end
  end
end
