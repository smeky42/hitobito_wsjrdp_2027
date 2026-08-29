# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Align the budget amounts of wsjrdp_cost_centers and wsjrdp_spheres with the
# project-wide convention that currency amounts are numeric(20, 3) (like
# datev_bookings and the Moss tables). Values are unchanged (widening only).
#
# The generated effective_total_budget column cannot be re-typed in place, so
# it is dropped and re-created with the same expression (duplicated from
# 20260822000100 -- migrations stay self-contained) at the new scale.

class ChangeBudgetScaleToThreeDecimals < ActiveRecord::Migration[7.1]
  TABLES = [:wsjrdp_cost_centers, :wsjrdp_spheres].freeze
  BUDGET_COLUMNS = [
    :budget_2025, :budget_2026, :budget_2027, :budget_2028, :explicit_total_budget
  ].freeze

  EFFECTIVE_TOTAL_BUDGET_SQL = <<~SQL.squish
    CASE
      WHEN coalesce(budget_2025, budget_2026, budget_2027, budget_2028) IS NULL
        THEN explicit_total_budget
      WHEN explicit_total_budget IS NULL
        OR abs(coalesce(budget_2025, 0) + coalesce(budget_2026, 0)
             + coalesce(budget_2027, 0) + coalesce(budget_2028, 0)) > abs(explicit_total_budget)
        THEN coalesce(budget_2025, 0) + coalesce(budget_2026, 0)
           + coalesce(budget_2027, 0) + coalesce(budget_2028, 0)
      ELSE explicit_total_budget
    END
  SQL

  def up
    change_scale(3)
  end

  def down
    change_scale(2)
  end

  private

  def change_scale(scale)
    TABLES.each do |table|
      remove_column table, :effective_total_budget
      BUDGET_COLUMNS.each do |column|
        change_column table, column, :decimal, precision: 20, scale: scale
      end
      add_column table, :effective_total_budget, :virtual,
        type: :decimal, precision: 20, scale: scale,
        stored: true, as: EFFECTIVE_TOTAL_BUDGET_SQL,
        comment: "Displayed total: yearly sum or explicit_total_budget, whichever is larger in absolute value; generated, not writable"
    end
  end
end
