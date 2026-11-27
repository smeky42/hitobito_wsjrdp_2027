# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddMossBankAccountColumnsToWsjrdpFinAccounts < ActiveRecord::Migration[7.1]
  def change
    change_table :wsjrdp_fin_accounts, bulk: true do |t|
      t.uuid :moss_bank_account_uuid, comment: "Moss API bank account `id`; NULL for accounts outside Moss"
      t.uuid :moss_organisation_uuid, comment: "Moss API field `organisationId`"
      t.string :moss_funding_type, comment: "Moss API field `fundingType`: DEBIT or CREDIT"
      t.string :moss_account_status, comment: "Moss API field `accountStatus`: ACTIVE or CLOSED"
      t.string :moss_currency, comment: "Moss API field `currency` (ISO 4217)"
      t.decimal :moss_balance, precision: 20, scale: 3, comment: "Moss API balance `balance.amount`, as last read"
      t.decimal :moss_available_balance, precision: 20, scale: 3,
        comment: "Moss API balance `availableBalance.amount`, as last read"
      t.datetime :moss_balance_first_seen_at, comment: "When the sync first read the current Moss balance"
      t.datetime :moss_removed_at, comment: "Set when a sync no longer returned the account; cleared when it comes back"
    end
    add_index :wsjrdp_fin_accounts, :moss_bank_account_uuid, unique: true, where: "moss_bank_account_uuid IS NOT NULL"
  end
end
