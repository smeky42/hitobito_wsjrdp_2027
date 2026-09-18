# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddIsUnitBudgetToAccounts < ActiveRecord::Migration[7.1]
  ACCOUNT_COMMENT = "Flag to indicate if a booking on this account belongs to the budget of a unit"

  BUDGET_TABLES = %i[wsjrdp_cost_centers wsjrdp_sub_cost_centers wsjrdp_spheres].freeze
  BUDGET_YEARS = (2025..2028)

  def up
    add_column :wsjrdp_ledger_accounts, :is_unit_budget, :boolean,
      default: true, null: false, comment: ACCOUNT_COMMENT
    add_column :wsjrdp_personal_accounts, :is_unit_budget, :boolean,
      default: true, null: false, comment: ACCOUNT_COMMENT
    add_column :wsjrdp_cost_centers, :is_unit_cost_center, :boolean,
      default: false, null: true

    # A unit's own cost center is numbered like the unit itself: one capital
    # letter and digits ("X1"). Its NAME is the prose form ("Unit X1"), so the
    # number is what carries the pattern.
    execute <<~SQL
      UPDATE wsjrdp_cost_centers
         SET is_unit_cost_center = TRUE
       WHERE number ~ '^[A-Z][0-9]+$'
    SQL

    # Every unit group whose WHOLE name is such a number gets the same-named cost
    # center appended to its list -- only where that cost center actually exists
    # and is not in the list yet, so the statement may be run again at any time.
    # The `?` is the jsonb "has key" operator, not a bind marker: #execute sends
    # the statement verbatim, without parameter substitution.
    execute <<~SQL
      UPDATE groups g
         SET additional_info = jsonb_set(COALESCE(g.additional_info, '{}'::jsonb),
                                         '{cost_center_numbers}',
                                         COALESCE(g.additional_info->'cost_center_numbers', '[]'::jsonb) || to_jsonb(g.name),
                                         true)
        FROM wsjrdp_cost_centers c
       WHERE g.type = 'Group::Unit'
         AND g.deleted_at IS NULL
         AND g.name ~ '^[A-Z][0-9]+$'
         AND c.number = g.name
         AND NOT (COALESCE(g.additional_info->'cost_center_numbers', '[]'::jsonb) ? g.name)
    SQL

    BUDGET_TABLES.each do |table|
      BUDGET_YEARS.each do |year|
        change_column_comment table, :"budget_#{year}", "Budget #{year}; NULL = not set"
      end
    end
  end

  def down
    BUDGET_TABLES.each do |table|
      BUDGET_YEARS.each do |year|
        change_column_comment table, :"budget_#{year}",
          "Signed budget #{year} (expenses negative); NULL = not set"
      end
    end

    remove_column :wsjrdp_cost_centers, :is_unit_cost_center
    remove_column :wsjrdp_personal_accounts, :is_unit_budget
    remove_column :wsjrdp_ledger_accounts, :is_unit_budget
  end
end
