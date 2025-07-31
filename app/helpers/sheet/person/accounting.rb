# frozen_string_literal: true

module Sheet
  class Person < Base
    class Accounting < Base
      self.parent_sheet = Sheet::Person
    end
  end
end
