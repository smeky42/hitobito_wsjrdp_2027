# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddWsjrdpFinAccountsDisplayAttrs < ActiveRecord::Migration[7.1]
  def change
    add_column :wsjrdp_fin_accounts, :position, :integer, null: true  # manual display order
    add_column :wsjrdp_fin_accounts, :servicer_short_name, :string, null: true,
      comment: "Short name of the account-servicing institution, for display"
    add_column :wsjrdp_fin_accounts, :account_product, :string, null: false, default: "unknown",
      comment: "Account product (code list in WsjrdpFinAccount)"
  end
end
