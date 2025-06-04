# frozen_string_literal: true

module Wsjrdp2027::EventAbility
  extend ActiveSupport::Concern

  included do
    on(Event) do
      class_side(:list_available, :typeahead).if_admin
    end

    on(Event::Course) do
      class_side(:list_available).if_admin
    end
  end
end
