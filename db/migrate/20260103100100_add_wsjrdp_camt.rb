# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddWsjrdpCamt < ActiveRecord::Migration[7.1]
  def change
    create_table "wsjrdp_camt_transactions", id: :serial, force: :cascade do |t|
      # mandatory
      t.string :camt_type, null: false  # e.g., "camt.052"
      t.string :account_identification, null: false
      t.string :account_servicer_reference, null: false, comment: "<AcctSvcrRef>"
      t.string :credit_debit_indication, null: false, comment: "<CdtDbtInd>"
      t.integer :amount_cents, null: false
      t.string :amount_currency, null: false, default: "EUR"
      t.date :value_date, null: false
      t.string :description, null: false

      # message
      t.string :message_identification, null: true, comment: "<MsgId>"
      t.datetime :message_creation_date_time, null: true, comment: "<CreDtTm>"

      # Rpt / Stmt / ...
      t.string :report_identification, null: true, comment: "<Stmt><Id>|<Rpt>..."
      t.integer :report_electronic_sequence_number, null: true, comment: "<Stmt><ElctrncSeqNb>|<Rpt>..."
      t.integer :report_legal_sequence_number, null: true, comment: "<Stmt><LglSeqNb>|<Rpt>..."
      t.integer :report_page_number, null: true, comment: "<Stmt><StmtPgntn><PgNb>|<Rpt>..."
      t.datetime :report_creation_date_time, null: true, comment: "<Stmt><CreDtTm>|<Rpt>..."

      # Ntry
      t.string :status, null: false, default: "NULL", comment: "<Ntry><Sts><Cd>"
      t.string :additional_entry_info, null: true, comment: "<AddtlNtryInf>"
      t.date :booking_date, null: true
      t.integer :number_of_transactions, null: false, default: 1, comment: "Number of <Ntry><NtryDtls><TxDtls>"

      # TxDtls
      t.integer :transaction_details_index, null: false, default: 0  # for uniqueness
      t.text :comment, null: false, default: ""
      t.jsonb :references, null: false, default: {}, comment: "<Ntry><NtryDtls><TxDtls><Refs>"
      t.string :endtoend_id, null: true
      t.string :mandate_id, null: true
      t.string :bank_transaction_code, null: true, comment: "<BkTxCd>"
      t.string :bank_transaction_code_dk, null: true  # Prtry for DK = Deutsche Kreditwirtschaft
      t.string :return_reason, null: true, comment: "<Ntry><NtryDtls><TxDtls><RtrInf><Rsn><Cd>"
      t.string :cdtr_name, null: true
      t.string :cdtr_iban, null: true
      t.string :cdtr_bic, null: true
      t.string :cdtr_address, null: true
      t.string :dbtr_name, null: true
      t.string :dbtr_iban, null: true
      t.string :dbtr_bic, null: true
      t.string :dbtr_address, null: true

      # metadata and references
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: true
      t.datetime :deleted_at, null: true
      t.bigint :entry_id, null: true, comment: "the entry this transaction belongs to"
      t.bigint :replaced_by_id, null: true, comment: "for soft delete"
      t.bigint :replaces_id, null: true, comment: "for soft delete"
      t.bigint :reversed_by_id, null: true, comment: "for reversal bookings"
      t.bigint :reverses_id, null: true, comment: "for reversal bookings"
      t.bigint :partially_reverses_id, null: true, comment: "for partial reversals"
      t.bigint :subject_id, null: true
      t.string :subject_type, null: true
      t.bigint :fin_account_id, null: true  # -> wsjrdp_fin_accounts
      t.bigint :payment_initiation_id, null: true  # -> wsjrdp_payment_initiations
      t.bigint :partially_reverses_payment_initiation_id, null: true  # -> wsjrdp_payment_initiations
      t.bigint :direct_debit_payment_info_id, null: true  # -> wsjrdp_direct_debit_payment_infos
      t.bigint :accounting_entry_id, null: true  # -> accounting_entries
      t.bigint :camt52_entry_id, null: true
      t.bigint :camt53_entry_id, null: true
      t.jsonb :ntry, null: true, comment: "<Ntry>"
      t.jsonb :tx_dtls, null: true, comment: "<TxDtls>"
      t.jsonb :additional_info, default: {}

      t.index [:account_identification]
      t.index [:subject_id, :subject_type]
      t.index [:account_identification, :camt_type, :account_servicer_reference, :transaction_details_index], unique: true, where: "deleted_at IS NULL"
    end

    create_table "wsjrdp_fin_accounts", id: :serial, force: :cascade do |t|

      # mandatory
      t.string :account_identification, null: false  # must be :iban if :iban is present!
      t.integer :opening_balance_cents, null: false
      t.string :opening_balance_currency, null: false
      t.date :opening_balance_date, null: false

      # optional
      t.string :iban, null: true
      t.string :short_name, null: true
      t.text :description, null: false, default: ""
      t.string :owner_name, null: true
      t.string :owner_address, null: true
      t.string :servicer_name, null: true
      t.string :servicer_bic, null: true
      t.string :servicer_address, null: true

      # metadata
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: true
      t.datetime :deleted_at, null: true
      t.string :status, null: false, default: "active", comment: "active, closed, deleted"
      t.jsonb :additional_info, default: {}

      t.index [:account_identification], unique: true, where: "deleted_at IS NULL"
    end

    # update accounting_entries
    add_column :accounting_entries, :return_reason, :string, null: true
    add_column :accounting_entries, :camt52_entry_id, :bigint, null: true  # -> wsjrdp_camt_transactions
    add_column :accounting_entries, :camt53_entry_id, :bigint, null: true  # -> wsjrdp_camt_transactions
    add_column :accounting_entries, :camt54_entry_id, :bigint, null: true  # -> wsjrdp_camt_transactions

    # update wsjrdp_payment_initiations
    add_column :wsjrdp_payment_initiations, :camt52_entry_id, :bigint, null: true  # -> wsjrdp_camt_transactions
    add_column :wsjrdp_payment_initiations, :camt53_entry_id, :bigint, null: true  # -> wsjrdp_camt_transactions
  end
end
