# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddVisibilityToBookkeepingMasterData < ActiveRecord::Migration[7.1]
  def change
    remove_check_constraint :wsjrdp_ledger_accounts,
      "visibility IN ('auto', 'visible', 'hidden')",
      name: "chk_ledger_account_visibility"

    change_column_comment :wsjrdp_ledger_accounts, :visibility,
      from: "Hitobito-specific, can be auto, visible (always visible) or hidden (never visible)",
      to: nil
    change_column_comment :wsjrdp_personal_accounts, :visibility,
      from: "Hitobito-specific, can be auto, visible (always visible) or hidden (never visible)",
      to: nil

    add_column :wsjrdp_cost_centers, :visibility, :string, default: "auto", null: false
    add_column :wsjrdp_spheres, :visibility, :string, default: "auto", null: false
    add_column :wsjrdp_fin_accounts, :visibility, :string, default: "auto", null: false
  end
end
