# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Sub cost centers refine a wsjrdp_cost_centers entry inside Hitobito, below
# the granularity DATEV and Moss know about. They are linked to their cost
# center by its number, the way the Moss tables link, and mirror the cost
# center columns: names, aliases, the yearly budgets with their explicit total
# and the free-text columns. A number is unique within its cost center only.
class AddWsjrdpSubCostCenters < ActiveRecord::Migration[7.1]
  # Displayed total budget (generated column): the yearly sum or the explicitly
  # set total, whichever has the LARGER ABSOLUTE VALUE. A numeric MAX would be
  # wrong here: budgets are signed (expenses negative, income positive), so
  # MAX(-25850, -10000) would pick the smaller envelope. All-years-NULL is
  # detected via coalesce (generation expressions allow no subqueries).
  # Duplicated from 20260828000300 -- migrations stay self-contained.
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

  def change
    create_table :wsjrdp_sub_cost_centers, id: :bigserial, force: :cascade,
      comment: "Hitobito-owned sub cost centers below a wsjrdp_cost_centers entry, linked by its number" do |t|
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :updated_at, null: true

      t.string :cost_center_number, null: false,
        comment: "The cost center this sub cost center belongs to (wsjrdp_cost_centers.number)"
      t.string :number, null: false,
        comment: "Sub cost center number, unique within its cost center"
      t.string :name, null: true
      t.string :short_name, null: true
      t.text :aliases, array: true, default: [], null: false,
        comment: "Hitobito-specific alternative names"

      t.boolean :delete_without_finance_permission, default: true, null: false
      t.string :visibility, default: "auto", null: false

      t.decimal :budget_2025, precision: 20, scale: 3, null: true,
        comment: "Signed budget 2025 (expenses negative); NULL = not set"
      t.decimal :budget_2026, precision: 20, scale: 3, null: true,
        comment: "Signed budget 2026 (expenses negative); NULL = not set"
      t.decimal :budget_2027, precision: 20, scale: 3, null: true,
        comment: "Signed budget 2027 (expenses negative); NULL = not set"
      t.decimal :budget_2028, precision: 20, scale: 3, null: true,
        comment: "Signed budget 2028 (expenses negative); NULL = not set"
      t.decimal :explicit_total_budget, precision: 20, scale: 3, null: true,
        comment: "Explicitly set total budget for the whole period; NULL = not set"

      t.jsonb :additional_info, null: false, default: {},
        comment: "Reserved for future use"

      t.virtual :display_short_name, type: :string, stored: true,
        as: "COALESCE(NULLIF(short_name, ''), NULLIF(name, ''), '')",
        comment: "Generated: short_name, falling back to name, then ''. " \
                 "The one place defining how a short display name is derived."
      t.text :description, null: false, default: ""
      t.text :comment, null: false, default: ""
      t.text :user_comment, null: false, default: "",
        comment: "Comment visible for users"

      t.virtual :effective_total_budget, type: :decimal, precision: 20, scale: 3,
        stored: true, as: EFFECTIVE_TOTAL_BUDGET_SQL,
        comment: "Displayed total: yearly sum or explicit_total_budget, whichever is larger in absolute value; generated, not writable"

      t.index [:cost_center_number, :number], unique: true,
        name: "index_wsjrdp_sub_cost_centers_on_cost_center_and_number"
    end

    add_index :datev_bookings, [:cost_center_number, :sub_cost_center_number],
      name: "index_datev_bookings_on_cost_center_and_sub_cost_center"
  end
end
