# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The wagon's additions to what a service token may do.
#
# The wagon's scopes (Wsjrdp2027::ServiceTokenScopes); their extras work only
# with an acting person (Wsjrdp2027::ServiceToken#effective_scopes).
#
# people:log, groups:log, events:log: the API key may :log what it may show
# of that area, where its substitute person with its Zugriffsbereich may
# :log it. In this wagon :log is the gate of the privileged view
# (doc/roles.md, "The :log convention").
#
# finance:read, finance:audit, finance:write, finance:manage: each gives the
# substitute person its finance permission (Wsjrdp2027::ServiceToken#dynamic_user),
# and the API key may the actions of every permission held (FINANCE_ACTIONS)
# on the finance models, on a person's and on a group's finance, where that
# person may them. An acting person's own tier caps the API key's.
module Wsjrdp2027::TokenAbility
  # Per finance permission: the actions on the ladder models, on the
  # person-level models, on a person and on a group. Each lists the actions
  # of the ones below as well (doc/roles.md, "Finance tiers"); :manage is
  # CanCanCan's wildcard.
  FINANCE_ACTIONS = {
    finance_read: {ladder: %i[show], person_level: [], person: [], group: []},
    finance_audit: {ladder: %i[show log], person_level: %i[show log], person: [], group: %i[show_finance]},
    finance: {ladder: %i[show log create update], person_level: %i[show log create update],
              person: %i[update_finance], group: %i[show_finance update_finance]},
    finance_manage: {ladder: %i[show log create update admin_finance manage],
                     person_level: %i[show log create update admin_finance manage],
                     person: %i[update_finance admin_finance destroy_finance],
                     group: %i[show_finance update_finance configure_finance]}
  }.freeze

  private

  def define_token_abilities
    super
    define_log_abilities
    define_finance_abilities
  end

  # The actions of every finance permission the scopes give.
  def define_finance_abilities
    held = token.finance_permissions.map { |permission| FINANCE_ACTIONS.fetch(permission) }
    return if held.empty?

    actions = ->(key) { held.flat_map { |entry| entry[key] }.uniq }
    delegate_to_dynamic_user(actions.call(:ladder), Wsjrdp2027::FinanceAccess.ladder_models)
    delegate_to_dynamic_user(actions.call(:person_level), Wsjrdp2027::FinanceAccess.person_level_models)
    delegate_to_dynamic_user(actions.call(:person), [Person, PersonDecorator])
    delegate_to_dynamic_user(actions.call(:group), [Group])
  end

  # Each action on the subjects, where the token's person may it.
  def delegate_to_dynamic_user(actions, subjects)
    actions.each do |action|
      can action, subjects do |subject|
        dynamic_user_ability.can?(action, subject)
      end
    end
  end

  def define_log_abilities
    define_person_log_abilities if token.people? && token.log_scope?(:people)
    define_group_log_abilities if token.groups? && token.log_scope?(:groups)
    define_event_log_abilities if token.events? && token.log_scope?(:events)
  end

  # The people TokenAbility#define_person_abilities lets the token show.
  def define_person_log_abilities
    below = token.layer_and_below_read? || token.layer_and_below_full?
    groups = below ? token_layer_and_below : [token.layer]
    can :log, [Person, PersonDecorator] do |person|
      Role.where(person: person, group: groups).present? && dynamic_user_ability.can?(:log, person)
    end
  end

  def define_group_log_abilities
    can :log, Group do |group|
      token_layer_and_below.include?(group) && dynamic_user_ability.can?(:log, group)
    end
  end

  def define_event_log_abilities
    can :log, Event do |event|
      event.groups.any? { |group| token_layer_and_below.include?(group) } &&
        dynamic_user_ability.can?(:log, event)
    end
  end
end
