# frozen_string_literal: true

module Wsjrdp2027::EventAbility
  extend ActiveSupport::Concern

  included do
    on(Event) do
      # Hides the group tab in the left sidebar
      class_side(:list_available, :typeahead).if_admin

      permission(:any).may(:manage_tags).none
      permission(:group_full).may(:manage_tags).none

      # In hitobito_wsjrdp_2027, :log is the generic "privileged view"
      # gate.  On events it controls advanced fields hidden behind
      # can?(:log, entry) like external_applications,
      # globally_visible, waiting_list, .... Core defines no :log
      # ability on Event, so without this grant nobody (except the
      # root superuser) may :log an event.
      #
      # `.if_layer_and_below_full_on_root` (core EventAbility) only
      # checks the user, not the event: anyone holding
      # layer_and_below_full in the root layer (CMT roles Admin,
      # Leader and Finance) may :log every event.  Unit and IST
      # managers hold layer_and_below_full on their own layer only, so
      # they gain nothing here.
      permission(:layer_and_below_full).may(:log).if_layer_and_below_full_on_root
    end

    on(Event::Course) do
      # Hides the group tab in the left sidebar
      class_side(:list_available).if_admin
    end
  end
end
