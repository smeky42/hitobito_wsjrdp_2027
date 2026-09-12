# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# What the admin tab (layouts/_wsjrdp_session_bar, doc/roles.md -> "The
# finance cap") needs: whether it shows -- for whom, and by the session's
# compact_admin_tab mode -- and what "demand" means for it.
module WsjrdpAdminTabHelper
  # Only for whoever is actually logged in with :admin, and then: always; on
  # demand, while one of the bars is missing; never otherwise -- the tab has
  # to be asked for. The mode is read first: that validates the session value
  # on every page, and spares the roles lookup while there is none.
  def compact_admin_tab?
    mode = compact_admin_tab
    return false if mode.nil? || !admin_tab_permitted?

    (mode == :always) || compact_admin_tab_demand?
  end

  # The person who actually logged in -- the origin user while impersonating,
  # never the impersonated person -- holds :admin or is root.
  def admin_tab_permitted?
    person = origin_user || current_user
    person.present? && (person.root? || person.groups_with_permission(:admin).present?)
  end

  # Demand: one of the two bars is missing -- no impersonation runs, or the
  # yellow bar is hidden -- so the menu is where the missing controls are.
  # With both bars up, they carry everything the menu offers.
  def compact_admin_tab_demand?
    origin_user.nil? || !finance_tier_bar?
  end

  # Whether the menu offers the person search: the person who actually logged
  # in may impersonate. While impersonating that is the origin user, whose
  # ability has to be built here -- the current one is the impersonated
  # person's.
  def admin_tab_may_impersonate?
    actor = origin_user
    return can?(:impersonate_user, Person) if actor.nil?

    Ability.new(actor).can?(:impersonate_user, Person)
  end
end
