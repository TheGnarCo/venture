module DeliService
  extend self
  include Venture

  def blt!(customer:, ticket:)
    as_event!(base_params: { customer:, ticket: }, fail_as: DeliErrorEvent) do
      blt = make_blt!()
      !(blt:)

      Success.new
    end

      
