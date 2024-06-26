class Venture::Success
  attr_reader :events, :effects

  def initialize(events: [], effects: [])
    @events  = events
    @effects = effects
  end
end
