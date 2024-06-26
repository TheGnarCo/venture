module Venture::Spec
  module Errors
    class TestEventError < Venture::Errors::EventError
      event Venture::Spec::Events::TestFailureEvent
    end

    class WidgetError < Venture::Errors::EventError; end
  end
end
