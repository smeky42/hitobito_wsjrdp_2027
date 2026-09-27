# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Rechte" of a service token as TokenAbility grants them: the Zugriffsbereich
# first, and the acting person where there is one, then per ticked kind
# whether the token only reads or also writes.
# The show page and the list both show this.
#
# What TokenAbility lets a token write:
# - people: update people, if the Zugriffsbereich is one with "Schreibrechte"
#   (the token's person holds that permission and must be allowed to update);
# - people and groups together: create, update and destroy roles, on the same
#   condition -- shown as a line of its own;
# - invoices: update invoices and their items, whatever the Zugriffsbereich.
# Everything else is read only. With people:log, groups:log or events:log
# that area adds ", Log", finance scopes add a line "Finanzen
# <highest tier>", and a last line names the stored scopes
# (Wsjrdp2027::ServiceTokenScopes).
module Wsjrdp2027::ServiceTokenDecorator
  def abilities
    lines = [h.content_tag(:strong, ::ServiceToken.human_attribute_name(permission))]
    lines << acting_person_description if acting_person
    lines += kinds.filter_map { |kind| ability_description(kind, ability_action(kind)) if public_send(kind) }
    lines << roles_description if people? && groups?
    lines << finance_description if finance_permissions.any?
    lines << scopes_description if scopes.any?
    safe_join(lines, h.tag(:br))
  end

  private

  def write_permission? = permission.to_s.end_with?("_full")

  def ability_action(kind)
    action = case kind
    when :people then write_permission? ? :read_write : :read
    when :invoices then :read_write
    else :read
    end
    log_scope?(kind) ? :"#{action}_log" : action
  end

  # Only what the acting person may do as well (Wsjrdp2027::ActingPersonTokenAbility).
  def acting_person_description
    h.t("service_tokens.abilities.acting_person", person: acting_person.to_s, id: acting_person.id)
  end

  # The highest finance permission the scopes give (Wsjrdp2027::TokenAbility).
  def finance_description
    safe_join([h.t("service_tokens.abilities.finance"),
      h.muted(h.t("wsjrdp.finance_tiers.#{finance_cap}"))], " ")
  end

  # The stored scopes as a script names them.
  def scopes_description
    h.muted(h.t("service_tokens.abilities.scopes", scopes: scopes.join(", ")))
  end

  def roles_description
    safe_join([::Role.model_name.human(count: 2),
      h.muted(h.t("service_tokens.abilities.#{write_permission? ? :read_write : :read}"))], " ")
  end
end
