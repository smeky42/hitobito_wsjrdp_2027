# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddMossBalanceMovements < ActiveRecord::Migration[7.1]

  def change

    add_column :wsjrdp_fin_accounts, :transaction_type, :string, default: "WsjrdpCamtTransaction", null: false
    add_column :wsjrdp_fin_accounts, :banking_url, :string, null: true

    reversible do |direction|
      direction.up do
        @next_fin_account_id = ActiveRecord::Base.connection.execute("SELECT nextval('wsjrdp_fin_accounts_id_seq')").first["nextval"]
        execute <<-SQL
INSERT INTO wsjrdp_fin_accounts (
  id, created_at, short_name, account_identification,
  opening_balance_cents, opening_balance_currency, opening_balance_date,
  owner_name, owner_address,
  banking_url,
  transaction_type
) VALUES (
  #{@next_fin_account_id}, NOW(), 'Moss Wallet', '',
  0, 'EUR', '2025-12-11',
  'Ring deutscher Pfadfinder*innenverbände e.V.', 'Chausseestraße 128/129, 10115 Berlin',
  'https://getmoss.com/app',
  'MossBalanceMovement'
);
        SQL
      end
      direction.down do
        @next_fin_account_id = 0
        execute <<-SQL
DELETE FROM wsjrdp_fin_accounts WHERE transaction_type = 'MossBalanceMovement';
        SQL
      end
    end

    create_table "moss_balance_movements", id: :serial, force: :cascade do |t|
      t.datetime "created_at", null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.datetime "updated_at", null: true
      t.bigint "fin_account_id", null: false, default: @next_fin_account_id
      t.bigint "subject_id", null: true
      t.string "subject_type", null: true
      t.text "comment", default: "", null: false
      t.string "status", null: true
      t.jsonb "additional_info", default: {}
      #
      t.string "unique_item_number", null: false
      t.string "moss_transaction_id", null: false
      t.integer "sub_row_number", null: false, default: 0
      t.string "transaction_state", null: true
      t.string "transaction_type", null: true
      # t.string "record_type", null: true
      # t.string "csv_line_type"
      t.date "payment_date", null: false
      t.date "booking_date", null: false
      # t.tring "period"
      t.decimal "amount_excl_vat", precision: 20, scale: 3, null: true
      t.decimal "amount", precision: 20, scale: 3, null: false
      t.string "currency", null: false
      t.decimal "original_amount_excl_vat", precision: 20, scale: 3, null: true
      t.decimal "original_amount", precision: 20, scale: 3, null: true
      t.string "original_currency", null: true
      t.decimal "conversion_rate", precision: 20, scale: 8, null: true
      t.decimal "conversion_rate_including_fees", precision: 20, scale: 8, null: true
      t.decimal "fees_amount", precision: 20, scale: 3, null: true
      t.decimal "payment_fee", precision: 20, scale: 3, null: true
      t.decimal "transaction_amount_excluding_fees", precision: 20, scale: 3, null: true
      t.string "supplier_account", null: true  # Kreditor Nr.
      t.string "supplier_name", null: true  # Kreditor Name
      t.string "account_number", null: true  # Sachkonto
      t.string "name_of_expense_account", null: true  # Name Sachkonto
      t.string "category", null: true
      t.string "moss_balance_account", null: true
      t.string "cash_in_transit_account", null: true
      t.string "reason_for_purchase", null: true
      t.string "note", null: false, default: ""
      t.string "recipient_account_number", null: true
      t.string "recipient_bank_code", null: true
      t.string "payment_reference", null: true
      t.string "invoice_number", null: true
      t.string "team_name", null: true
      t.string "cardholder", null: true
      t.string "client_number", null: true
      t.date "first_export_date", null: true
      t.string "moss_expense_id", null: true
      t.string "moss_invoice_id", null: true
      t.string "moss_reimbursement_id", null: true
      t.string "moss_attachment_url", null: true

      t.index ["unique_item_number"], name: "index_moss_balance_movements_unique_item_number", unique: true
      t.index ["moss_transaction_id", "sub_row_number"], name: "index_moss_balance_movements_tx_id_sub_row", unique: true
      t.index ["subject_type", "subject_id"], name: "index_moss_balance_movements_subject"
    end

    add_column :accounting_entries, :moss_balance_movement_id, :bigint, null: true
  end
end
