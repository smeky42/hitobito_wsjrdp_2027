# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  # "Moss" -- the second sub-item of the Finanzen main-nav section (between
  # Zahlungsverkehr and Buchhaltung). Holds the Moss overview and the card
  # transactions list. This is also the sheet of Fin::MossController (controller
  # "fin/moss" -> Sheet::Fin::Moss), so /fin/moss renders the tabs directly.
  # See doc/navigation.md.
  class Fin::Moss < Base
    # Übersicht is an exact-match tab (no_alt) so it does not also light up on the
    # /fin/moss/card_transactions sub-paths.
    tab "fin.tabs.overview", :moss_path, no_alt: true
    tab "fin.tabs.card_transactions", :moss_card_transactions_path

    def left_nav?
      true
    end

    def render_left_nav
      view.render("fin/left_nav")
    end

    def title
      I18n.t("fin.nav.moss")
    end
  end
end
