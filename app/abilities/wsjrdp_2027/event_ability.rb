# frozen_string_literal: true

module Wsjrdp2027::EventAbility
  extend ActiveSupport::Concern

  included do
    on(Event) do
      # Hides the group tab in the left sidebar
      class_side(:list_available, :typeahead).if_admin

      permission(:any).may(:manage_tags).none
      permission(:group_full).may(:manage_tags).none
    end

    on(Event::Course) do
      # Hides the group tab in the left sidebar
      class_side(:list_available).if_admin
    end
  end
end
