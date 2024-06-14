require 'ostruct'

module Venture::Config
  extend self

  def configuration; @configuration ||= OpenStruct.new(); end
  def configure; yield configuration; end

  def event_base_class; configuration.event_base_class || Venture::Event; end
  def table_name_prefix; configuration.table_name_prefix || "ve_"; end

  def valid_event_class?(event_class)
    event_class.is_a?(Class) && event_class.ancestors.include?(event_base_class)
  end
end
