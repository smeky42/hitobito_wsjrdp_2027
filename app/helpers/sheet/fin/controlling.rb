# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  # "Controlling" -- the last sub-item of the Finanzen main-nav section. The
  # area is new and still empty; it holds nothing but its overview page so far.
  # This is the sheet of Fin::ControllingController (controller
  # "fin/controlling" -> Sheet::Fin::Controlling).
  class Fin::Controlling < Base
    # Übersicht is an exact-match tab (no_alt) so it will not also light up on
    # the /fin/controlling/... sub-paths a later step adds.
    tab "fin.tabs.overview", :controlling_path, no_alt: true

    def left_nav?
      true
    end

    def render_left_nav
      view.render("fin/left_nav")
    end

    def title
      I18n.t("fin.nav.controlling")
    end
  end
end
