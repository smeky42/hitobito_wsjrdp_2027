# frozen_string_literal: true

module Wsjrdp2027::SubscriptionAbility
  extend ActiveSupport::Concern

  included do
    on(Subscription) do
      # Replaced original permissions:
      # permission(:group_full).may(:manage).in_same_group
      permission(:group_full).may(:manage).none
    end
  end
end
