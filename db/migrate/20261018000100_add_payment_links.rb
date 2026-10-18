# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The links of the Zahlungsverkehr (doc/fin/payments.md) between the bank
# statement and what was sent to the bank:
#
# - a bank transaction names the debit it concerns
#   (direct_debit_pre_notification_id): a return, or -- once statements with
#   transaction details (camt.053/054) are read -- a debit's single collection;
#   whether it collects or returns, the transaction itself says (return_reason,
#   debit_credit). A collective credit names its Sammler and order through the
#   columns it already has, now with foreign keys;
# - indexes for the joins: the end-to-end ids and mandates the returns are
#   matched by, the bank transaction of an accounting entry, the entry
#   (Ntry) a transaction detail (TxDtls) belongs to;
# - additional_info on the Sammler, as orders and debits have it -- e.g. for
#   the references a bank assigned in place of ours (bank_* keys).
class AddPaymentLinks < ActiveRecord::Migration[7.1]
  def change
    add_reference :wsjrdp_camt_transactions, :direct_debit_pre_notification,
      foreign_key: {to_table: :wsjrdp_direct_debit_pre_notifications, on_delete: :nullify},
      comment: "The debit this bank transaction concerns: its return, or its single collection (TxDtls)"
    add_foreign_key :wsjrdp_camt_transactions, :wsjrdp_payment_initiations,
      column: :payment_initiation_id, on_delete: :nullify
    add_foreign_key :wsjrdp_camt_transactions, :wsjrdp_direct_debit_payment_infos,
      column: :direct_debit_payment_info_id, on_delete: :nullify
    add_index :wsjrdp_camt_transactions, :payment_initiation_id
    add_index :wsjrdp_camt_transactions, :direct_debit_payment_info_id
    add_index :wsjrdp_camt_transactions, :entry_id

    add_foreign_key :accounting_entries, :wsjrdp_camt_transactions,
      column: :camt_transaction_id, on_delete: :nullify
    add_index :accounting_entries, :camt_transaction_id
    add_index :accounting_entries, :endtoend_id
    add_index :wsjrdp_direct_debit_pre_notifications, :endtoend_id
    add_index :wsjrdp_direct_debit_pre_notifications, :mandate_id

    add_column :wsjrdp_direct_debit_payment_infos, :additional_info, :jsonb, null: false, default: {}
  end
end
