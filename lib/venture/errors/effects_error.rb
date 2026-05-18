class Venture::Errors::EffectsError < Venture::Errors::EventError
  event Venture::Events::EffectsErrorEvent
end
