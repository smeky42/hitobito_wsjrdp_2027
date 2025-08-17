# frozen_string_literal: true

#  Copyright (c) 2025, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.


# rails app:db:migrate:up VERSION=20250816080808
# rails app:db:migrate:down VERSION=20250816080808

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

    create_table :payment_initiations do |t|
      t.datetime :created_at, null: false
      t.string :schema, null: false
      t.string :message_identification, null: false
      t.integer :number_of_transactions, null: false
      t.bigint :control_sum, null: false
    end

    rename_column :accounting_entries, :subject_id, :people_id
    rename_column :accounting_entries, :ammount, :amount_cents
    rename_column :accounting_entries, :comment, :description
    add_column :accounting_entries, :comment, :text, default: ''
    add_column :accounting_entries, :amount_currency, :string, default: "EUR"
    add_column :accounting_entries, :payment_initiation_id, :bigint, null: true
    add_column :accounting_entries, :updated_at, :datetime, null: true
    add_column :accounting_entries, :value_date, :date, null: true
    add_column :accounting_entries, :end_to_end_identifier, :string, null: true
    add_column :accounting_entries, :reversed_by_accounting_entry_id, :bigint, null: true
    add_column :accounting_entries, :reverses_accounting_entry_id, :bigint, null: true
    add_column :accounting_entries, :sepa_status, :string, default: 'ok'

  end
end
