# frozen_string_literal: true

module Sheet
  class Person < Base
    class Medical < Base
      self.parent_sheet = Sheet::Person
    end
  end
end
