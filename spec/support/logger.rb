module Venture::Spec
  module Logger
    extend self

    def messages; @messages ||= []; end

    [:info, :error].each do |m|
      define_method(m) do |message|
        messages << [m, message]
      end
    end
  end
end
