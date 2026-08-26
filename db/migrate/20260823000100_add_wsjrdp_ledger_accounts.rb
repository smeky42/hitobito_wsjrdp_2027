# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddWsjrdpLedgerAccounts < ActiveRecord::Migration[7.1]
  def change
    create_table :wsjrdp_ledger_accounts, id: :bigserial, force: :cascade,
                 comment: "Ledger accounts (Sachkonten)" do |t|
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :updated_at, null: true

      t.string :number, null: false
      t.string :name, null: true
      t.string :short_name, null: true
      t.virtual :display_short_name, type: :string, stored: true,
                as: "COALESCE(NULLIF(short_name, ''), NULLIF(name, ''), '')",
                comment: "Generated: short_name, falling back to name, then ''. " \
                         "The one place defining how a short display name is derived."
      t.text :aliases, array: true, null: false, default: [],
             comment: "Hitobito-specific alternative names"
      t.text :description, null: false, default: ""
      t.text :comment, null: false, default: ""
      t.string :visibility, null: false, default: "auto",
               comment: "Hitobito-specific, can be auto, visible (always visible) or hidden (never visible)"
      t.string :account_type, null: false, default: "UNKNOWN",
               comment: "short code: BANK/TRANSIT/CLEARING/LIABILITY/INCOME/EXPENSE/EQUITY/UNKNOWN"

      # ---- DATEV specific columns

      t.string :datev_purpose, null: true, comment: "DATEV Kontenzweck"
      t.integer :datev_function_type, null: true, comment: "DATEV Hauptfunktionstyp (HFTyp), 0 = no Hauptfunktion"
      t.integer :datev_function_number, null: true, comment: "DATEV Hauptfunktionsnummer (Funktion); only set for Automatik-/Funktionskonten"
      t.integer :datev_additional_function, null: true, comment: "DATEV Zusatzfunktion"
      t.jsonb :other_datev_columns, null: false, default: {}, comment: "Other DATEV-specific columns"

      # ---- Moss-specific columns
      t.string :moss_status, null: true,
               comment: "active or deactivated; NULL = unknown to Moss (counts as deactivated)"
      t.string :moss_category, null: true, comment: "Moss Category (e.g., OTHER, TRAVEL_AND_TRANSPORTATION)"
      t.jsonb :other_moss_columns, null: false, default: {}, comment: "other Moss-specific columns"

      t.jsonb :additional_info, null: false, default: {}, comment: "Reserved for future use"

      t.index :number, unique: true
      t.check_constraint "number !~ '^[1-9]\\d{5}$'",
                         name: "chk_ledger_account_number_not_personal_account"
      t.check_constraint "visibility IN ('auto', 'visible', 'hidden')",
                         name: "chk_ledger_account_visibility"
    end
  end
end
