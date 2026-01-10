# frozen_string_literal: true

module Wsjrdp2027::GroupAbility
  extend ActiveSupport::Concern

  included do
    on(Group) do
      # Show events and mailing lists to users with pemissions to read the group, instead of everyone
      permission(:any)
        .may(:index_events, :"index_event/courses", :index_mailing_lists)
        .nobody
      permission(:group_read)
        .may(:index_events, :"index_event/courses", :index_mailing_lists)
        .in_same_group
      permission(:group_and_below_read)
        .may(:index_events, :"index_event/courses", :index_mailing_lists)
        .in_same_group_or_below
      permission(:layer_read)
        .may(:index_events, :"index_event/courses", :index_mailing_lists)
        .in_same_layer
      permission(:layer_and_below_read)
        .may(:index_events, :"index_event/courses", :index_mailing_lists)
        .in_same_layer_or_below
      permission(:group_full).may(:log, :index_mailing_lists).nobody
      permission(:group_full).may(:show_statistics).in_same_group
      end
  end
end
