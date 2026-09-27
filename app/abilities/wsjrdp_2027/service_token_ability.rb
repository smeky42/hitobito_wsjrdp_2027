# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Who manages API keys (service tokens): an admin (a role with the :admin
# permission). An admin shows and deletes the API keys of every layer, and
# makes, edits and re-keys only those of the root group. The core lets every
# :layer_full and :layer_and_below_full holder manage the API keys of their
# own layer; in this wagon those are the CMT leaders, the finance roles, the
# unit managers and the IST leaders, none of whom manages API keys.
#
# The core's rules are replaced with .none: re-registering the same
# permission and action replaces the core's constraint (AbilityDsl::Store#add
# is last-wins), and CanCan ORs its rules, so only removing a rule takes its
# grant away. The group's :index_service_tokens (the "API-Keys" button and
# the list) is held by admins on every layer (Wsjrdp2027::GroupAbility), and
# the model refuses a new API key outside the root group
# (Wsjrdp2027::ServiceToken).
module Wsjrdp2027::ServiceTokenAbility
  extend ActiveSupport::Concern

  included do
    on(ServiceToken) do
      # Replaced original permissions:
      # permission(:layer_and_below_full).may(:manage).service_token_in_same_layer
      # permission(:layer_full).may(:manage).service_token_in_same_layer
      permission(:layer_and_below_full).may(:manage).none
      permission(:layer_full).may(:manage).none
      # :show and :destroy on every layer, so an API key of another layer can
      # be looked at and removed; :create (with :new), :update (with :edit)
      # and :regenerate_token (the new token) in the root group only.
      permission(:admin).may(:show, :destroy).all
      permission(:admin).may(:create, :update, :regenerate_token).service_token_in_root_group
    end
  end

  # The API key belongs to the root group (Group.root).
  def service_token_in_root_group
    subject.layer_group_id.present? && subject.layer_group_id == ::Group.root&.id
  end
end
