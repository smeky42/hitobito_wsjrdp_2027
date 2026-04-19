# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  class Fin::WsjrdpFin < Base
    tab "fin.tabs.accounts", :wsjrdp_fin_accounts_path
    tab "fin.tabs.person_fees", :fin_person_fees_path
    tab "fin.tabs.plans", :wsjrdp_payment_plans_path

    def title
      "Finanzen"
    end
  end
end
