# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  class Contingent::WsjrdpCmt < Base
    tab "contingent.tabs.overview", :contingent_contingent_path
    tab "contingent.tabs.cmt", :contingent_cmt_path

    def title
      "German Contingent - CMT / JPT"
    end
  end
end
