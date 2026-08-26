# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  # "Buchhaltung" -- the second sub-item of the Finanzen main-nav section,
  # holding the DATEV bookkeeping overview and the bookings list.
  class Fin::Accounting < Base
    # Übersicht is an exact-match tab (no_alt) so it does not also light up on the
    # /bookkeeping/accounts... sub-paths.
    tab "fin.tabs.overview", :bookkeeping_path, no_alt: true
    tab "fin.tabs.bookings", :bookings_path
    tab "fin.tabs.ledger_accounts", :ledger_accounts_path
    tab "fin.tabs.cost_centers", :cost_centers_path
    tab "fin.tabs.suppliers", :personal_accounts_path

    def left_nav?
      true
    end

    def render_left_nav
      view.render("fin/left_nav")
    end

    def title
      I18n.t("fin.nav.accounting")
    end
  end
end
