class Venture::Errors::EventError < RuntimeError
  # the event class corresponding to the class of exception; e.g., every time
  # a driver submission is rejected because it's invalid we should record a
  # DriverInvalid event. this is specified at the class level
  def self.event(event_class = nil)
    if event_class
      if Venture::Config.valid_event_class?(event_class)
        @_event_class = event_class
      else
        raise ArgumentError, "#{event_class} is not a valid event class"
      end
    else
      @_event_class
    end
  end

  def initialize(*args, **params, &block)
    @params = params
    super(*args, &block)
  end

  attr_reader :params

  # additional error events that may be specified on the instance at the
  # call site; e.g., when a driver submission is invalid, we want to take note
  # of certain kinds of errors, like conflicts or invalid CORI consent dates.
  # follows the same declarative format used for the events: argument to
  # EventService::Success, a hash where the keys are event classes and values
  # are param hashes or lists thereof
  def additional_events
    params[:additional_events] || {}
  end

  # allow event service to report what events were created via exceptions of
  # this kind
  def created_events
    @created_events ||= []
  end
end
