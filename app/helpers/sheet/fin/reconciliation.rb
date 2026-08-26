# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  # "Abstimmung" -- the third sub-item of the Finanzen main-nav section:
  # matching accounting entries with DATEV bookings.
  class Fin::Reconciliation < Base
    # Übersicht is an exact-match tab (no_alt) so it does not also light up on
    # the /reconciliation/... sub-paths.
    tab "fin.tabs.overview", :reconciliation_path, no_alt: true
    tab "fin.tabs.participant_fees", :reconciliation_participant_fees_path

    def left_nav?
      true
    end

    def render_left_nav
      view.render("fin/left_nav")
    end

    def title
      I18n.t("fin.nav.reconciliation")
    end
  end
end
