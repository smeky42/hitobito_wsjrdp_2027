# frozen_string_literal: true

module Sheet
  class Group < Base
    class Patrol < Base
      self.parent_sheet = Sheet::Group

      def model_name
        "patrol"
      end
    end
  end
end
