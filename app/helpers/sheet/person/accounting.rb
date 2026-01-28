# frozen_string_literal: true

module Sheet
  class Person < Base
    class Accounting < Base
      class_attribute :always_render_parent

      self.parent_sheet = Sheet::Person
      self.always_render_parent = true
    end
  end
end
