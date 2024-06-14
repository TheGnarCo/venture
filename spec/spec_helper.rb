require 'active_record'
require 'venture'

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
Venture::Migrate::CreateEvents.new.migrate(:up)
