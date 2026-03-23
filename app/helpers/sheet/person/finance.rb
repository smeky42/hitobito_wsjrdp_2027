# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  class Person < Base
    class Finance < Base
      tab "people.finance.tabs.fee", :person_fee_path_with_group, if: :edit
      tab "people.finance.tabs.spend", :person_spend_path_with_group, if: :edit

      self.parent_sheet = Sheet::Person

      def model_name
        @model_name ||= "person"
      end

      def title
        "#{entry} - Finanzen"
      end
    end
  end
end
