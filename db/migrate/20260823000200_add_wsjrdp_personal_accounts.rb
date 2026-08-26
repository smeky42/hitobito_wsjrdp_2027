# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddWsjrdpPersonalAccounts < ActiveRecord::Migration[7.1]
  def change
    create_table :wsjrdp_personal_accounts, id: :bigserial, force: :cascade,
                 comment: "Personal accounts (Debitoren, Kreditoren)" do |t|
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
      t.string :account_type, null: false, default: "CREDITOR",
               comment: "CREDITOR (Kreditor/Lieferant) or DEBITOR (Debitor/Kunde). "
      t.bigint :represented_person_id, null: true,
               comment: "Optional n:1 (<-> people): set when this Debitor/Kreditor " \
                        "represents a real person with a Hitobito account. " \
                        "Hitobito-specific; no import writes it."

      t.string :iban, null: true
      t.string :bic, null: true

      t.string :street, null: true, comment: "DATEV Straße (Rechnungsadresse)"
      t.string :address_second_line, null: true, comment: "DATEV Adresszusatz (Rechnungsadresse)"
      t.string :post_code, null: true, comment: "DATEV Postleitzahl (Rechnungsadresse)"
      t.string :city, null: true, comment: "DATEV Ort (Rechnungsadresse)"
      t.string :country, null: true, comment: "DATEV Land (Rechnungsadresse)"

      # ---- DATEV-specific columns

      t.string :datev_short_name, null: true,
               comment: "DATEV Kurzbezeichnung (max. 15 chars)"
      t.string :datev_nummer_fremdsystem, null: true,
               comment: "DATEV Nummer Fremdsystem (max. 15 chars) the first 15 characters of the Moss supplier UUID"
      t.jsonb :other_datev_columns, null: false, default: {},
              comment: "Other DATEV-specific columns (for a future DATEV Personenkonten-Stammdaten export)"

      # ---- Moss-specific columns

      t.string :moss_uuid, null: true,
               comment: "Moss supplier UUID (API field `id`); only obtainable via the Moss API"
      t.string :moss_status, null: true,
               comment: "Moss Status active or deactivated; " \
                        "NULL = unknown to Moss (counts as deactivated)"
      t.string :moss_type, null: true, comment: "Moss Type"
      t.string :moss_account_holder_name, null: true
      t.string :moss_default_currency, null: true
      t.string :moss_vat_id, null: true
      t.string :moss_default_payment_method, null: true, comment: "Moss payment method, e.g., SEPA"
      t.string :moss_default_ledger_account_number, null: true
      t.string :moss_default_cost_center_number, null: true
      t.string :moss_default_sphere_number, null: true
      t.string :moss_default_team_name, null: true
      t.jsonb :other_moss_columns, null: false, default: {},
              comment: "Other Moss-specific columns from the Moss supplier export (VAT Code/Rate/Name, payment terms, ...)"

      # ---- other columns, indices and constraints

      t.jsonb :additional_info, null: false, default: {},
              comment: "Reserved for future, yet-unknown data (JSONB); empty by default."

      t.index :number, unique: true
      t.index :represented_person_id
      # Personal accounts are 6-digit: Debitoren 1xxxxx-6xxxxx, Kreditoren
      # 7xxxxx-9xxxxx (DATEV standard ranges at 5-digit Sachkontenlaenge).
      t.check_constraint "number ~ '^[1-9]\\d{5}$'",
                         name: "chk_personal_account_number_six_digits"
      t.check_constraint "(account_type = 'CREDITOR' AND number ~ '^[7-9]') OR " \
                         "(account_type = 'DEBITOR' AND number ~ '^[1-6]')",
                         name: "chk_personal_account_type_matches_number"
    end

    add_foreign_key :wsjrdp_personal_accounts, :people, column: :represented_person_id
  end
end
