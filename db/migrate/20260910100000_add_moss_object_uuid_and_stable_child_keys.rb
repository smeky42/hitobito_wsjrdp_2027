# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Key the three Moss levels on ids that do not change between export profiles.
# L1 is identified by the generated `moss_object_uuid` -- the reimbursement or
# invoice id, and the first seen Transaction ID for a card payment or top-up;
# every Transaction ID a row has been seen under stays in
# `all_moss_transaction_uuids`. L2 is identified by `moss_expense_uuid` (a
# shell row carries its transaction's `moss_object_uuid`), L3 by
# `(moss_expense_id, sub_row_number)`.
class AddMossObjectUuidAndStableChildKeys < ActiveRecord::Migration[7.1]
  def up
    bad = select_value(<<~SQL.squish).to_i
      SELECT count(*) FROM moss_transactions
       WHERE cardinality(all_moss_transaction_uuids) = 0
          OR NOT (moss_transaction_uuid = ANY (all_moss_transaction_uuids))
    SQL
    if bad > 0
      raise ActiveRecord::MigrationError,
        "#{bad} moss_transactions row(s) with an empty array or a moss_transaction_uuid missing from it"
    end

    # ---- L1: the identity of the row
    add_column :moss_transactions, :moss_object_uuid, :virtual, type: :uuid, stored: true, null: false,
      as: "COALESCE(moss_reimbursement_uuid, moss_invoice_uuid, moss_transaction_uuid)",
      comment: "Identity of the row: Moss Expense id (reimbursement, invoice) or the first seen Transaction ID (card, top-up)"
    add_index :moss_transactions, :moss_object_uuid, unique: true, name: "index_moss_transactions_object_uuid"
    change_column_comment :moss_transactions, :moss_transaction_uuid,
      "First seen CSV Transaction ID (card + balance exports); every id seen is in all_moss_transaction_uuids"

    # ---- L2: moss_expense_uuid is the key
    execute <<~SQL # shells follow the transaction; a no-op on today's data
      UPDATE moss_expenses e SET moss_expense_uuid = t.moss_object_uuid
        FROM moss_transactions t
       WHERE t.id = e.moss_transaction_id AND e.type <> 'MossReimbursementExpense'
         AND e.moss_expense_uuid IS DISTINCT FROM t.moss_object_uuid
    SQL
    bad = select_value(<<~SQL.squish).to_i
      SELECT count(*) FROM moss_expenses e JOIN moss_transactions t ON t.id = e.moss_transaction_id
       WHERE e.moss_expense_uuid IS NULL
          OR (e.type <> 'MossReimbursementExpense' AND e.moss_expense_uuid <> t.moss_object_uuid)
    SQL
    raise ActiveRecord::MigrationError, "#{bad} moss_expenses row(s) without a usable moss_expense_uuid" if bad > 0

    change_column_null :moss_expenses, :moss_expense_uuid, false
    change_column_comment :moss_expenses, :moss_expense_uuid,
      "CSV Unique Expense ID (reimbursement export); card, invoice and top-up shells: the transaction's moss_object_uuid"
    remove_index :moss_expenses, name: "index_moss_expenses_expense_uuid"
    add_index :moss_expenses, :moss_expense_uuid, unique: true, name: "index_moss_expenses_expense_uuid"
    remove_index :moss_expenses, name: "index_moss_expenses_transaction_expense_number"
    add_index :moss_expenses, [:moss_transaction_id, :expense_number], unique: true,
      name: "index_moss_expenses_transaction_expense_number"
    remove_column :moss_expenses, :moss_transaction_uuid

    # ---- L3: the split is numbered within its expense
    add_column :moss_bookings, :sub_row_number, :integer,
      comment: "CSV Sub-row Number of the defining export: split within the card transaction (card export) / within the expense (reimbursement export), line within the invoice (invoice export), 1 for a top-up"
    execute "UPDATE moss_bookings SET sub_row_number = substr(booking_unique_item_number, 38)::integer"
    change_column_null :moss_bookings, :sub_row_number, false
    add_index :moss_bookings, [:moss_expense_id, :sub_row_number], unique: true, name: "index_moss_bookings_expense_sub_row"
    remove_index :moss_bookings, name: "index_moss_bookings_unique_item_number"
    remove_column :moss_bookings, :booking_unique_item_number
    remove_column :moss_bookings, :moss_transaction_uuid
  end

  def down
    add_column :moss_bookings, :moss_transaction_uuid, :uuid, comment: "Denormalised from the transaction"
    add_column :moss_bookings, :booking_unique_item_number, :string,
      comment: "Constructed: <transaction uuid>_<CSV Sub-row Number> (card, invoice, top-up) / <CSV Unique Expense ID>_<CSV Sub-row Number> (reimbursement)"
    execute <<~SQL
      UPDATE moss_bookings b
         SET moss_transaction_uuid = t.moss_transaction_uuid,
             booking_unique_item_number =
               CASE WHEN t.type = 'MossReimbursement' THEN e.moss_expense_uuid::text
                    ELSE t.moss_transaction_uuid::text END || '_' || b.sub_row_number
        FROM moss_transactions t, moss_expenses e
       WHERE t.id = b.moss_transaction_id AND e.id = b.moss_expense_id
    SQL
    change_column_null :moss_bookings, :moss_transaction_uuid, false
    change_column_null :moss_bookings, :booking_unique_item_number, false
    add_index :moss_bookings, :booking_unique_item_number, unique: true, name: "index_moss_bookings_unique_item_number"
    remove_index :moss_bookings, name: "index_moss_bookings_expense_sub_row"
    remove_column :moss_bookings, :sub_row_number

    add_column :moss_expenses, :moss_transaction_uuid, :uuid, comment: "Denormalised; part of the natural key below"
    execute <<~SQL
      UPDATE moss_expenses e SET moss_transaction_uuid = t.moss_transaction_uuid
        FROM moss_transactions t WHERE t.id = e.moss_transaction_id
    SQL
    change_column_null :moss_expenses, :moss_transaction_uuid, false
    remove_index :moss_expenses, name: "index_moss_expenses_transaction_expense_number"
    add_index :moss_expenses, [:moss_transaction_uuid, :expense_number], unique: true,
      name: "index_moss_expenses_transaction_expense_number"
    remove_index :moss_expenses, name: "index_moss_expenses_expense_uuid"
    add_index :moss_expenses, :moss_expense_uuid, name: "index_moss_expenses_expense_uuid"
    change_column_null :moss_expenses, :moss_expense_uuid, true
    change_column_comment :moss_expenses, :moss_expense_uuid,
      "CSV Unique Expense ID (reimbursement export) / CSV Invoice ID (invoice export) / CSV Transaction ID (card + balance exports)"

    remove_index :moss_transactions, name: "index_moss_transactions_object_uuid"
    remove_column :moss_transactions, :moss_object_uuid
    change_column_comment :moss_transactions, :moss_transaction_uuid,
      "CSV Transaction ID (card + balance exports) - most recent seen; see also all_moss_transaction_uuids"
  end
end
