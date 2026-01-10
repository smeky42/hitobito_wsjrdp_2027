# frozen_string_literal: true

module Wsjrdp2027::MailingListAbility
  extend ActiveSupport::Concern

  included do
    on(::MailingList) do
      # Replaced original permissions:
      # permission(:group_full).may(:show, :index_subscriptions).in_same_group
      # permission(:group_full).may(:create, :update, :destroy).in_same_group_if_active
      # permission(:group_full)
      #   .may(:export_subscriptions)
      #   .in_same_group_if_no_subscriptions_in_below_groups
      permission(:group_full).may(:show, :index_subscriptions).in_same_group
      permission(:group_full).may(:create, :update, :destroy, :export_subscriptions).nobody
    end
  end
end
