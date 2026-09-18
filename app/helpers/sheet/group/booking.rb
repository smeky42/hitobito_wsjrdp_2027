# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  class Group < Base
    # One booking of the group, below its Buchhaltung tab. Like
    # Sheet::Group::Bookkeeping it inherits the sub-tabs and the group entry
    # from Sheet::Group::Finance and changes only the title.
    #
    # Both tabs stay active here without an `alt:` of their own: a tab's own
    # path_method is already part of its alt_paths, and the last pass of
    # Wsjrdp2027::Sheet::Base#find_active_tab matches those as a PREFIX
    # (Sheet::Tab::Renderer#alt_path_of?) -- "/groups/8/finance/bookkeeping" is
    # the beginning of this page's path. An `alt:` naming the booking's own path
    # helper would not work either way: the sheet builds a tab's paths from its
    # path_args, which carry the group alone and not the booking's id.
    class Booking < Sheet::Group::Finance
      def title
        "#{entry} - Buchung"
      end
    end
  end
end
