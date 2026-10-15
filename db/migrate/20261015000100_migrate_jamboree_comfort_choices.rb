# frozen_string_literal: true

class MigrateJamboreeComfortChoices < ActiveRecord::Migration[7.1]
  COMFORT_ATTRS = %w[
    comfortable_on_water
    comfortable_in_water
    comfortable_without_balance
    comfortable_in_crowd
    comfortable_flashing_lights
    comfortable_loud_noise
    comfortable_confined_space
  ].freeze

  def up
    selected = COMFORT_ATTRS.map do |attr|
      "COALESCE((jamboree_data ->> '#{attr}') = 'true', false)"
    end.join(" OR ")
    choices = COMFORT_ATTRS.flat_map do |attr|
      ["'#{attr}'", "NOT ((#{selected}) AND COALESCE((jamboree_data ->> '#{attr}') = 'true', false))"]
    end.join(", ")

    execute <<~SQL
      UPDATE people
      SET jamboree_data = jamboree_data || jsonb_build_object(#{choices})
    SQL
  end
end