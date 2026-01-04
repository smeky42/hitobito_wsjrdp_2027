# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class ChangeCamtTxLinking < ActiveRecord::Migration[7.1]
  def change
    # Update wsjrdp_camt_transactions
    add_column :wsjrdp_camt_transactions, :entry_or_details, :string, null: false, default: "entry", comment: "'entry' (Ntry) or 'details' (TxDtls)"
    remove_column :wsjrdp_camt_transactions, :camt52_entry_id, :bigint
    remove_column :wsjrdp_camt_transactions, :camt53_entry_id, :bigint
    remove_column :wsjrdp_camt_transactions, :accounting_entry_id, :bigint
    reversible do |direction|
      direction.up do
        execute <<-SQL
UPDATE wsjrdp_camt_transactions SET entry_or_details = 'entry' WHERE entry_or_details IS NULL;
        SQL
      end
    end

    # Update accounting_entries
    rename_column :accounting_entries, :camt52_entry_id, :camt_transaction_id
    remove_column :accounting_entries, :camt53_entry_id, :bigint
    remove_column :accounting_entries, :camt54_entry_id, :bigint
    add_column :accounting_entries, :booking_date, :date
    reversible do |direction|
      direction.up do
        execute <<-SQL
UPDATE accounting_entries SET value_date = created_at::DATE WHERE value_date IS NULL;
UPDATE accounting_entries SET booking_date = value_date WHERE booking_date IS NULL;
        SQL
      end
    end
    change_column_null :accounting_entries, :value_date, false
    change_column_null :accounting_entries, :booking_date, false
  end
end
