# frozen_string_literal: true

module Wsjrdp2027::VariousAbility
  extend ActiveSupport::Concern

  included do
    on(LabelFormat) do
      class_side(:index).if_admin
    end
  end
end
