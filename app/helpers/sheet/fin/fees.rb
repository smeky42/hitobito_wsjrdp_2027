# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  # "Beiträge" -- the second sub-item of the Finanzen main-nav section: its
  # overview page (/fin/fees), the people with a special finance situation
  # (/fin/person_fees) and the installment plans (/fin/payment_plans).
  #
  # This sheet also serves the overview controller (Fin::FeesController ->
  # Sheet::Fin::Fees); the Übersicht tab is the area's link on /fin -- see
  # Fin::OverviewHelper#fin_areas.
  class Fin::Fees < Base
    # Übersicht is an exact-match tab (no_alt) so it does not also light up on
    # the section's other pages.
    tab "fin.tabs.overview", :fees_path, no_alt: true
    tab "fin.tabs.person_fees", :fin_person_fees_path
    tab "fin.tabs.plans", :wsjrdp_payment_plans_path

    def left_nav?
      true
    end

    def render_left_nav
      view.render("fin/left_nav")
    end

    def title
      I18n.t("fin.nav.fees")
    end
  end
end
