# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Bring wsjrdp_cost_centers and wsjrdp_spheres up to par with
# wsjrdp_ledger_accounts/wsjrdp_personal_accounts:
# - generated display_short_name
# - Hitobito-owned free-text columns description and comment
# - NULL semantics for moss_status (NULL = unknown to Moss)
class AddDisplayColumnsToWsjrdpCostCentersAndSpheres < ActiveRecord::Migration[7.1]
  def change
    add_column :wsjrdp_cost_centers, :display_short_name, :virtual,
      type: :string, stored: true,
      as: "COALESCE(NULLIF(short_name, ''), NULLIF(name, ''), '')",
      comment: "Generated: short_name, falling back to name, then ''. " \
               "The one place defining how a short display name is derived."
    add_column :wsjrdp_cost_centers, :description, :text, null: false, default: ""
    add_column :wsjrdp_cost_centers, :comment, :text, null: false, default: ""
    change_column_null :wsjrdp_cost_centers, :moss_status, true
    change_column_default :wsjrdp_cost_centers, :moss_status, from: "active", to: nil
    change_column_comment :wsjrdp_cost_centers, :moss_status,
      from: "Moss Status: active or deactivated",
      to: "Moss Status: active or deactivated; " \
          "NULL = unknown to Moss (counts as deactivated)"

    add_column :wsjrdp_spheres, :display_short_name, :virtual,
      type: :string, stored: true,
      as: "COALESCE(NULLIF(short_name, ''), NULLIF(name, ''), '')",
      comment: "Generated: short_name, falling back to name, then ''. " \
               "The one place defining how a short display name is derived."
    add_column :wsjrdp_spheres, :description, :text, null: false, default: ""
    add_column :wsjrdp_spheres, :comment, :text, null: false, default: ""
    change_column_null :wsjrdp_spheres, :moss_status, true
    change_column_default :wsjrdp_spheres, :moss_status, from: "active", to: nil
    change_column_comment :wsjrdp_spheres, :moss_status,
      from: "Moss Status: active or deactivated",
      to: "Moss Status: active or deactivated; " \
          "NULL = unknown to Moss (counts as deactivated)"
  end
end
