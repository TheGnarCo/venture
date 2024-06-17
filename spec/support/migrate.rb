module Venture::Spec::Migrate
  class CreateWidgets < ActiveRecord::Migration[5.0]
    def change
      create_table :ve_widgets do |t|
        t.string :name, null: false
      end
    end
  end
end
