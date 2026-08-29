# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Rename the DATEV Kontenart column `account_type` -> `account_kind`
# on the master-data tables, so the name matches datev_bookings, where
# `account_type` is now the polymorphic target class
# (WsjrdpLedgerAccount / WsjrdpPersonalAccount) and the Kontenart
# classification lives in `account_kind`. Postgres carries the
# check-constraint expression through the column rename automatically;
# only the constraint NAME is updated to match.
class RenameAccountTypeToAccountKindOnMasterData < ActiveRecord::Migration[7.1]
  def up
    rename_column :wsjrdp_ledger_accounts, :account_type, :account_kind
    rename_column :wsjrdp_personal_accounts, :account_type, :account_kind
    rename_check_constraint :wsjrdp_personal_accounts, "chk_personal_account_type_matches_number", "chk_personal_account_kind_matches_number"
  end

  def down
    rename_check_constraint :wsjrdp_personal_accounts, "chk_personal_account_kind_matches_number", "chk_personal_account_type_matches_number"
    rename_column :wsjrdp_personal_accounts, :account_kind, :account_type
    rename_column :wsjrdp_ledger_accounts, :account_kind, :account_type
  end

  private

  def rename_check_constraint(table, from, to)
    execute("ALTER TABLE #{table} RENAME CONSTRAINT #{from} TO #{to}")
  end
end
