# frozen_string_literal: true

module Sheet
  class Person < Base
    class Print < Base
      extend ActiveSupport::Concern

      self.parent_sheet = Sheet::Person
    end 
  end
end

