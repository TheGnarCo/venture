module Venture::Spec
  module Events
    class TestOkEvent < Venture.event_base_class
      def self.params(params)
        params.merge(validation_message: "success")
      end
    end

    class TestOkEvent2 < Venture.event_base_class
      def self.params(params)
        params.merge(validation_message: "success")
      end
    end

    class TestFailureEvent < Venture.event_base_class
      def self.params(params)
        params.merge(validation_message: "failure")
      end
    end
  end
end
