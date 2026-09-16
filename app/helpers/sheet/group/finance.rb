# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  class Group < Base
    class Finance < Base
      tab "groups.finance.tabs.bookkeeping",
        :group_finance_bookkeeping_path,
        if: :show_finance

      self.parent_sheet = Sheet::Group

      def model_name
        "group"
      end

      # The finance sheets show the group of the group sheet itself; the
      # route helpers take that group once, not once per sheet level.
      def path_args
        parent_sheet.path_args
      end

      def title
        "#{entry} - Finanzen"
      end
    end
  end
end
