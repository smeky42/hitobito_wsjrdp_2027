# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddBookkeepingAccountToWsjrdpFinAccounts < ActiveRecord::Migration[7.1]
  def up
    change_table :wsjrdp_fin_accounts do |t|
      t.string :bookkeeping_account_number, null: true,
        comment: "Number of the (DATEV) bookkeeping account this bank account/wallet maps to"
      t.string :bookkeeping_account_type, null: true, default: "WsjrdpLedgerAccount",
        comment: "Polymorphic type for bookkeeping_account_number (default WsjrdpLedgerAccount)"
    end
    add_index :wsjrdp_fin_accounts,
      %i[bookkeeping_account_type bookkeeping_account_number],
      name: "index_wsjrdp_fin_accounts_on_bookkeeping_account"
  end

  def down
    remove_index :wsjrdp_fin_accounts,
      name: "index_wsjrdp_fin_accounts_on_bookkeeping_account"
    remove_column :wsjrdp_fin_accounts, :bookkeeping_account_number
    remove_column :wsjrdp_fin_accounts, :bookkeeping_account_type
  end
end
