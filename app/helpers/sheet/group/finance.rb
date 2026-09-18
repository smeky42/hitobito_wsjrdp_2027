# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  class Group < Base
    class Finance < Base
      # No `alt:` for the booking page below the Buchhaltung
      # (/groups/:id/finance/bookkeeping/bookings/:id): a tab's own path_method
      # is already part of its alt_paths and is matched as a PREFIX in the last
      # pass of Wsjrdp2027::Sheet::Base#find_active_tab, so the bookkeeping path
      # covers everything below it. The booking's own path helper could not be
      # used here anyway -- the sheet builds a tab's paths from its path_args,
      # which carry the group alone and not the booking's id.
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
