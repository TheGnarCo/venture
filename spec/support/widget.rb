module Venture::Spec
  class Widget < ActiveRecord::Base
    self.table_name = "ve_widgets"
    validates_presence_of :name
  end

  class CreateWidgets < ActiveRecord::Migration[5.0]
    def change
      create_table "ve_widgets" do |t|
        t.string :name, null: false
        t.timestamps
      end
    end
  end
end
