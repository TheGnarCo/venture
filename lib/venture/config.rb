require 'ostruct'

module Venture::Config
  extend self

  def configuration; @configuration ||= OpenStruct.new(); end
  def configure; yield configuration; end

  def event_base_class
    configuration.event_base_class || Venture::Event
  end

  def event_data_column_type; configuration.event_data_column_type || :json; end

  def default_error_event_class
    configuration.default_error_event_class || Venture::Events::ErrorEvent
  end

  def logger
    configuration.logger || ActiveRecord::Base.logger
  end

  def table_name_prefix; configuration.table_name_prefix || "ve_"; end

  def valid_event_class?(event_class)
    event_class.is_a?(Class) && event_class.ancestors.include?(event_base_class)
  end
end
