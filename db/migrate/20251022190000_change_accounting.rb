# frozen_string_literal: true

#  Copyright (c) 2025, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

class ChangeAccounting < ActiveRecord::Migration[7.1]

  def change
    reversible do |direction|
      direction.up do
        execute <<-SQL
CREATE SEQUENCE IF NOT EXISTS "accounting_entries_id_seq"
  CACHE 10
  OWNED BY "accounting_entries"."id"
  ;
SELECT setval('accounting_entries_id_seq', MAX(id) + 1) FROM "accounting_entries";
ALTER TABLE ONLY "accounting_entries" ALTER COLUMN id SET DEFAULT nextval('accounting_entries_id_seq'::regclass);
UPDATE people SET sepa_status = 'ok' WHERE sepa_status = 'OK';
UPDATE people SET sepa_status = 'in_review' WHERE sepa_status = 'In Überprüfung';
UPDATE people SET sepa_status = 'missing' WHERE sepa_status = 'Zahlung ausstehend';
        SQL
        change_column :accounting_entries, :id, :bigint, null: false
      end
      direction.down do
        execute <<-SQL
ALTER TABLE ONLY "accounting_entries" ALTER COLUMN id DROP DEFAULT;
DROP SEQUENCE IF EXISTS "accounting_entries_id_seq";
UPDATE people SET sepa_status = 'OK' WHERE sepa_status = 'ok';
UPDATE people SET sepa_status = 'In Überprüfung' WHERE sepa_status = 'in_review';
UPDATE people SET sepa_status = 'Zahlung ausstehend' WHERE sepa_status = 'missing';
        SQL
      end
    end

    create_table :wsjrdp_payment_initiations do |t|
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: true
      t.string :status, null: false, default: "planned", comment: "One of planned, canceled, xml_generated"
      t.string :sepa_schema, null: true
      t.string :message_identification, null: true
      t.integer :number_of_transactions, null: true
      t.bigint :control_sum, null: true
      t.string :initiating_party_name, null: true
      t.string :initiating_party_iban, null: true
      t.string :initiating_party_bic, null: true
    end

    create_table :wsjrdp_direct_debit_payment_infos do |t|
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: true
      t.belongs_to :payment_initiation, null: true, foreign_key: { to_table: :wsjrdp_payment_initiations }
      t.string :payment_information_identification, null: true
      t.boolean :batch_booking, null: false, default: true
      t.integer :number_of_transactions, null: true
      t.bigint :control_sum, null: true
      t.string :payment_type_instrument, null: false, default: "CORE"
      t.string :sequence_type, null: false, default: "OOFF"  # e.g., OOFF
      t.date :requested_collection_date, null: false
      t.string :cdtr_name, null: true
      t.string :cdtr_iban, null: true
      t.string :cdtr_bic, null: true
      t.string :creditor_id, null: false, default: "DE81WSJ00002017275"  # SEPA Gläubiger-Identifikationsnummer
    end

    create_table :wsjrdp_direct_debit_pre_notifications do |t|
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: true
      t.belongs_to :payment_initiation, null: false, foreign_key: { to_table: :wsjrdp_payment_initiations }
      t.belongs_to :direct_debit_payment_info, null: false, foreign_key: { to_table: :wsjrdp_direct_debit_payment_infos }
      t.bigint :subject_id, null: true
      t.string :subject_type, null: true, default: "Person"
      t.bigint :author_id, null: true
      t.string :author_type, null: true, default: "Person"
      t.boolean :try_skip, null: true, comment: "Use to request skipping of the notified payment"
      t.string :payment_status, null: false, default: "pre_notified", comment: "One of pre_notified, skipped, xml_generated"
      t.string :email_from, null: false, default: "anmeldung@worldscoutjamboree.de"
      t.string :email_to, null: true, array: true
      t.string :email_cc, null: true, array: true
      t.string :email_bcc, null: true, array: true
      t.string :email_reply_to, null: true, array: true
      t.string :dbtr_name, null: false
      t.string :dbtr_iban, null: false
      t.string :dbtr_bic, null: true
      t.string :dbtr_address, null: true
      t.string :amount_currency, null: false, default: "EUR"
      t.integer :amount_cents, null: false
      t.string :sequence_type, null: false, default: "OOFF", comment: "One of OOFF, FRST, RCUR, FNAL"
      t.date :collection_date, null: true
      t.string :mandate_id, null: true
      t.date :mandate_date, null: true
      t.string :description, null: true
      t.string :endtoend_id, null: true
      t.string :payment_role, null: true
      t.string :creditor_id, null: false, default: "DE81WSJ00002017275"  # SEPA Gläubiger-Identifikationsnummer
    end

    add_index :wsjrdp_direct_debit_pre_notifications, [:author_type, :author_id]
    add_index :wsjrdp_direct_debit_pre_notifications, [:subject_type, :subject_id]

    add_column :accounting_entries, :subject_type, :string, null: true, default: "Person"
    add_column :accounting_entries, :author_type, :string, null: true, default: "Person"
    add_index :accounting_entries, [:author_type, :author_id]
    remove_index :accounting_entries, [:subject_id]
    add_index :accounting_entries, [:subject_type, :subject_id]
    rename_column :accounting_entries, :ammount, :amount_cents
    rename_column :accounting_entries, :comment, :description
    add_reference :accounting_entries, :payment_initiation, null: true, foreign_key: { to_table: :wsjrdp_payment_initiations }
    add_reference :accounting_entries, :direct_debit_payment_info, null: true, foreign_key: { to_table: :wsjrdp_direct_debit_payment_infos }
    add_reference :accounting_entries, :direct_debit_pre_notification, null: true, foreign_key: { to_table: :wsjrdp_direct_debit_pre_notifications }
    add_column :accounting_entries, :comment, :text, null: false, default: ""
    add_column :accounting_entries, :amount_currency, :string, null: false, default: "EUR"
    add_column :accounting_entries, :updated_at, :datetime, null: true
    add_column :accounting_entries, :value_date, :date, null: true
    add_column :accounting_entries, :end_to_end_identifier, :string, null: true
    add_reference :accounting_entries, :reversed_by, null: true, foreign_key: { to_table: :accounting_entries }
    add_reference :accounting_entries, :reverses, null: true, foreign_key: { to_table: :accounting_entries }
    add_column :accounting_entries, :new_sepa_status, :string, null: true, default: "ok"
    add_column :accounting_entries, :mandate_id, :string, null: true
    add_column :accounting_entries, :mandate_date, :date, null: true
    add_column :accounting_entries, :debit_sequence_type, :string, null: true
    add_column :accounting_entries, :cdtr_name, :string, null: true
    add_column :accounting_entries, :cdtr_iban, :string, null: true
    add_column :accounting_entries, :cdtr_bic, :string, null: true
    add_column :accounting_entries, :cdtr_address, :string, null: true
    add_column :accounting_entries, :dbtr_name, :string, null: true
    add_column :accounting_entries, :dbtr_iban, :string, null: true
    add_column :accounting_entries, :dbtr_bic, :string, null: true
    add_column :accounting_entries, :dbtr_address, :string, null: true

    change_column_default :people, :sepa_status, from: nil, to: "ok"

    reversible do |direction|
      direction.up do
        execute <<-SQL
UPDATE accounting_entries SET author_type = 'Person' WHERE author_id IS NOT NULL AND author_id > 0;
        SQL
      end
    end

  end
end
