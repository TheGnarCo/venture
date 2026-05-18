class Venture::Errors::ReturnError < Venture::Errors::EventError
  event Venture::Events::ReturnErrorEvent
end
