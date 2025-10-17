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

        SQL
        change_column :accounting_entries, :id, :bigint, null: false
      end
      direction.down do
        execute <<-SQL
ALTER TABLE ONLY "accounting_entries" ALTER COLUMN id DROP DEFAULT;
DROP SEQUENCE IF EXISTS "accounting_entries_id_seq";
        SQL
      end
    end

    create_table :wsjrdp_payment_initiations do |t|
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: true
      t.string :sepa_schema, null: false
      t.string :message_identification, null: false
      t.integer :number_of_transactions, null: false
      t.bigint :control_sum, null: false
      t.string :initiating_party_name, null: false
      t.string :initiating_party_iban, null: false
      t.string :initiating_party_bic, null: true
    end

    create_table :wsjrdp_direct_debit_payment_infos do |t|
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: true
      t.belongs_to :payment_initiation, null: true, foreign_key: { to_table: :wsjrdp_payment_initiations }
      t.string :payment_information_identification, null: false
      t.boolean :batch_booking, default: true
      t.integer :number_of_transactions, null: false
      t.bigint :control_sum, null: false
      t.string :payment_type_instrument, default: "CORE"
      t.string :sequence_type, default: "OOFF"  # e.g., OOFF
      t.date :requested_collection_date, null: false
      t.string :cdtr_name, null: false
      t.string :cdtr_iban, null: false
      t.string :cdtr_bic, null: true
      t.string :creditor_id, null: false  # SEPA Gläubiger-Identifikationsnummer
    end

    rename_column :accounting_entries, :subject_id, :person_id
    add_foreign_key :accounting_entries, :people, column: :person_id
    rename_column :accounting_entries, :ammount, :amount_cents
    rename_column :accounting_entries, :comment, :description
    add_reference :accounting_entries, :payment_initiation, null: true, foreign_key: { to_table: :wsjrdp_payment_initiations }
    add_reference :accounting_entries, :direct_debit_payment_info, null: true, foreign_key: { to_table: :wsjrdp_direct_debit_payment_infos }
    add_column :accounting_entries, :comment, :text, default: ""
    add_column :accounting_entries, :amount_currency, :string, default: "EUR"
    add_column :accounting_entries, :updated_at, :datetime, null: true
    add_column :accounting_entries, :value_date, :date, null: true
    add_column :accounting_entries, :end_to_end_identifier, :string, null: true
    add_reference :accounting_entries, :reversed_by, null: true, foreign_key: { to_table: :accounting_entries }
    add_reference :accounting_entries, :reverses, null: true, foreign_key: { to_table: :accounting_entries }
    add_column :accounting_entries, :new_sepa_status, :string, default: "ok"
    add_column :accounting_entries, :mandate_id, :string, null: true
    add_column :accounting_entries, :mandate_date, :date, null: true
    add_column :accounting_entries, :sepa_debit_type, :string, null: true
    add_column :accounting_entries, :cdtr_name, :string, null: true
    add_column :accounting_entries, :cdtr_iban, :string, null: true
    add_column :accounting_entries, :cdtr_bic, :string, null: true
    add_column :accounting_entries, :cdtr_address, :string, null: true
    add_column :accounting_entries, :dbtr_name, :string, null: true
    add_column :accounting_entries, :dbtr_iban, :string, null: true
    add_column :accounting_entries, :dbtr_bic, :string, null: true
    add_column :accounting_entries, :dbtr_address, :string, null: true
  end
end
