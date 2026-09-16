# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  # "Verwaltung" -- the last sub-item of the Finanzen main-nav section: the
  # per-group finance access (/fin/admin/finance_groups) and the cost centers
  # of a group (/fin/admin/group_cost_centers).
  #
  # The area has no page of its own; /fin/admin renders the first tab. Both
  # tabs carry the area's gate, so somebody without :configure_finance sees no
  # tab -- and with that no card on /fin either, because
  # Fin::OverviewHelper#fin_areas drops an area whose tabs are all hidden.
  class Fin::Admin < Base
    # ::Group, not Group: inside `module Sheet` the bare constant resolves to
    # the core's Sheet::Group, which would make the condition silently false.
    tab "fin.tabs.finance_groups", :fin_admin_finance_groups_path,
      if: ->(view, *) { view.can?(:configure_finance, ::Group) }
    tab "fin.tabs.group_cost_centers", :fin_admin_group_cost_centers_path,
      if: ->(view, *) { view.can?(:configure_finance, ::Group) }

    def left_nav?
      true
    end

    def render_left_nav
      view.render("fin/left_nav")
    end

    def title
      I18n.t("fin.nav.admin")
    end
  end
end
