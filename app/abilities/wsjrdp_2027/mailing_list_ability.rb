# frozen_string_literal: true

module Wsjrdp2027::MailingListAbility
  extend ActiveSupport::Concern

  included do
    on(::MailingList) do
      permission(:group_full).may(:show, :create, :index_subscriptions, :update).nobody
      permission(:group_full).may(:update, :destroy).in_same_group_if_active

      # permission(:group_full).may(:show, :index_subscriptions).in_same_group
      # permission(:group_full).may(:update, :destroy).in_same_group_if_active
      # permission(:group_full)
      #   .may(:export_subscriptions)
      #   .in_same_group_if_no_subscriptions_in_below_groups
    end
  end
end
