# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  # "Synchronisation" in the Finanzen sub-navigation: the overview, Moss API
  # and Moss CSV (Fin::SyncController). Every tab carries the area's gate,
  # so without :configure_finance the area has no card on /fin either.
  class Fin::Sync < Base
    # ::Group, not Group: inside `module Sheet` the bare constant is the
    # core's Sheet::Group.
    GATE = ->(view, *) { view.can?(:configure_finance, ::Group) }

    tab "fin.tabs.overview", :fin_sync_path, no_alt: true, if: GATE
    tab "fin.tabs.moss_api", :fin_sync_moss_api_path, if: GATE
    tab "fin.tabs.moss_csv", :fin_sync_moss_csv_path, if: GATE

    def left_nav?
      true
    end

    def render_left_nav
      view.render("fin/left_nav")
    end

    def title
      I18n.t("fin.nav.sync")
    end
  end
end
