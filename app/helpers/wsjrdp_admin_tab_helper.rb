# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# What the admin tab (layouts/_wsjrdp_session_bar, doc/roles.md -> "The
# finance cap") needs: whether it shows -- for whom, and by the session's
# admin_tab mode -- and what "demand" means for it.
module WsjrdpAdminTabHelper
  # Milliseconds the admin tab's impersonation button stays locked before it
  # can be pressed (doc/roles.md -> "The finance cap"). Three seconds
  # everywhere; the only way to change it is the dev-only override
  # dev-only-overrides/local_dev_only_impersonate_delay.rb, which each
  # developer has to symlink in by hand and which sets
  # config.x.wsjrdp_impersonate_delay_ms. Nothing a request carries has any
  # say.
  DEFAULT_IMPERSONATE_DELAY_MS = 3000
  MAX_IMPERSONATE_DELAY_MS = 60_000

  def impersonate_delay_ms
    milliseconds = Rails.application.config.x.wsjrdp_impersonate_delay_ms
    return DEFAULT_IMPERSONATE_DELAY_MS unless milliseconds.is_a?(Integer)

    milliseconds.clamp(0, MAX_IMPERSONATE_DELAY_MS)
  end

  # Only for whoever is actually logged in with :admin, and then: always; on
  # demand, while one of the bars is missing; never in :hidden, which is what
  # an unasked-for session says -- the tab has to be asked for. The mode is
  # read first: that validates the session value on every page, and spares
  # the roles lookup while the tab is off anyway.
  def admin_tab?
    return false if admin_tab == :hidden || !admin_tab_permitted?

    (admin_tab == :always) || admin_tab_demand?
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
  def admin_tab_demand?
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
