require 'active_record'
require 'venture'
require 'rspec/rails'

Venture.configure do |venture|
  venture.event_base_class = Class.new
end

RSpec.configure do |rspec|
  rspec.use_transactional_fixtures = true
end
