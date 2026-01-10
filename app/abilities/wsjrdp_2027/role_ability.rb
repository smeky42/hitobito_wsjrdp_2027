# frozen_string_literal: true

module Wsjrdp2027::RoleAbility
  extend ActiveSupport::Concern

  included do
    on(Role) do
      # Replaced original permission:
      # permission(:group_full).may(:create, :update, :destroy, :terminate)
      #   .in_same_group_if_active
      permission(:group_full).may(:create, :update, :destroy, :terminate).none
    end
  end
end
