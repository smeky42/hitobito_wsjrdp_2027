# frozen_string_literal: true

module Sheet
  class Group < Base
    class Map < Base
      self.parent_sheet = Sheet::Group

      def model_name
        "map"
      end
    end
  end
end
