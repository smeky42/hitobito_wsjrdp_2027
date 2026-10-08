# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class CreateWsjrdpPaymentNotices < ActiveRecord::Migration[7.1]
  def change
    create_table :wsjrdp_payment_notices do |t|
      # No foreign keys: the row keeps the ids of a deleted person.
      t.string :subject_type, null: false, default: "Person"
      t.bigint :subject_id, null: false
      t.string :author_type, null: true, default: "Person"
      t.bigint :author_id, null: true
      # What the payment is for, e.g. a deregistration.
      t.string :ref_type, null: true
      t.bigint :ref_id, null: true
      t.string :status, null: false, default: "created"
      # On a notice replacing another one.
      t.references :replaces, null: true, foreign_key: {to_table: :wsjrdp_payment_notices, on_delete: :nullify}
      # Signed like an accounting entry: positive is paid by the person,
      # negative is paid to the person.
      t.decimal :amount, null: false, precision: 20, scale: 3
      # The sum of the accounting entries linked to the notice.
      t.decimal :booked_amount, null: false, precision: 20, scale: 3, default: 0
      t.string :amount_currency, null: false, default: "EUR"
      # The RF reference in the remittance information; a remainder may be
      # asked for under the code of the first notice.
      t.string :payment_code, null: false
      t.string :description, null: false
      t.date :value_date, null: true
      t.string :endtoend_id, null: true
      t.string :cdtr_name, null: true
      t.string :cdtr_iban, null: true
      t.string :cdtr_bic, null: true
      t.string :cdtr_address, null: true
      t.string :dbtr_name, null: true
      t.string :dbtr_iban, null: true
      t.string :dbtr_bic, null: true
      t.string :dbtr_address, null: true
      t.string :email_from, null: true
      t.string :email_to, null: true, array: true
      t.string :email_cc, null: true, array: true
      t.string :email_bcc, null: true, array: true
      t.string :email_reply_to, null: true, array: true
      t.references :receipt_document, null: true, foreign_key: {to_table: :wsjrdp_documents, on_delete: :nullify}
      t.datetime :receipt_created_at, null: true
      t.jsonb :receipt_options, null: false, default: {}
      t.jsonb :receipt_snapshot, null: false, default: {}
      # Shown to the person; from then on the notice is fixed.
      t.datetime :announced_at, null: true
      # Set when the notice reaches a final status.
      t.datetime :closed_at, null: true
      t.text :comment, null: false, default: ""
      t.jsonb :additional_info, null: false, default: {}
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :updated_at, null: true

      t.index :payment_code
      t.index [:subject_type, :subject_id], name: "index_wsjrdp_payment_notices_on_subject"
      t.index [:author_type, :author_id], name: "index_wsjrdp_payment_notices_on_author"
      t.index [:ref_type, :ref_id], name: "index_wsjrdp_payment_notices_on_ref"
      t.index :status
    end

    add_reference :accounting_entries, :payment_notice, null: true,
      foreign_key: {to_table: :wsjrdp_payment_notices, on_delete: :nullify}

    add_reference :wsjrdp_direct_debit_pre_notifications, :ref, null: true, polymorphic: true,
      index: {name: "index_wsjrdp_direct_debit_pre_notifications_on_ref"}
    add_reference :wsjrdp_direct_debit_pre_notifications, :replaces, null: true,
      foreign_key: {to_table: :wsjrdp_direct_debit_pre_notifications, on_delete: :nullify},
      index: {name: "index_wsjrdp_direct_debit_pre_notifications_on_replaces_id"}
    add_reference :wsjrdp_direct_debit_pre_notifications, :receipt_document, null: true,
      foreign_key: {to_table: :wsjrdp_documents, on_delete: :nullify},
      index: {name: "index_wsjrdp_direct_debit_pre_notifications_on_receipt_document"}
  end
end
