# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddCommentsToDatevBookingsAndExtendMossTransactions < ActiveRecord::Migration[7.1]
  def up
    add_column :datev_bookings, :comment, :text, null: false, default: ""
    add_column :datev_bookings, :user_comment, :text, null: false, default: "", comment: "Comment visible for users"

    add_column :moss_transactions, :all_moss_transaction_uuids, :uuid, array: true,
      null: false, default: [],
      comment: "All Transaction Id's this row stands for; contains moss_transaction_uuid"

    add_column :moss_transactions, :sender_iban, :string, null: true, comment: "CSV Bank account (custom statement)"
    add_column :moss_transactions, :sender_bic, :string, null: true, comment: "CSV Bank account (custom statement)"
    add_column :moss_transactions, :sender_name, :string, null: true
    add_column :moss_transactions, :value_date, :date, null: true, comment: "CSV Value date (custom statement)"

    execute <<~SQL.squish
      UPDATE moss_transactions
         SET all_moss_transaction_uuids = ARRAY[moss_transaction_uuid]
    SQL

    add_index :moss_transactions, :all_moss_transaction_uuids, using: :gin,
      name: "index_moss_transactions_all_uuids"

    add_index :moss_transactions, :moss_reimbursement_uuid, unique: true,
      where: "moss_reimbursement_uuid IS NOT NULL",
      name: "index_moss_transactions_reimbursement_uuid"
    add_index :moss_transactions, :moss_invoice_uuid, unique: true,
      where: "moss_invoice_uuid IS NOT NULL",
      name: "index_moss_transactions_invoice_uuid"

    change_column_comment :moss_transactions, :moss_transaction_uuid,
      "CSV Transaction ID (card + balance exports) - most recent seen; see also all_moss_transaction_uuids"
  end

  def down
    change_column_comment :moss_transactions, :moss_transaction_uuid,
      "CSV Transaction ID (card + balance exports)"
    remove_index :moss_transactions, name: "index_moss_transactions_invoice_uuid"
    remove_index :moss_transactions, name: "index_moss_transactions_reimbursement_uuid"

    remove_index :moss_transactions, name: "index_moss_transactions_all_uuids"
    remove_column :moss_transactions, :all_moss_transaction_uuids
    remove_column :moss_transactions, :sender_iban
    remove_column :moss_transactions, :sender_bic
    remove_column :moss_transactions, :sender_name
    remove_column :moss_transactions, :value_date
    remove_column :datev_bookings, :user_comment
    remove_column :datev_bookings, :comment
  end
end
