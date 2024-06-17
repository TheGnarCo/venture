class Venture::Spec::Widget < ActiveRecord::Base
  self.table_name = "ve_widgets"
  validates_presence_of :name
end
