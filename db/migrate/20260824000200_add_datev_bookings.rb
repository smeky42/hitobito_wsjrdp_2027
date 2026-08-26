# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Stores bookings extracted from DATEV "Primanota" exports (Buchungsstapel).
# Column names use financial English; the DB comments name the original DATEV
# field (German) each column is derived from.
#
# The DATEV export only carries a sign-less "Umsatz" plus an "S/H" (Soll/Haben)
# flag, so the importer stores just those inputs -- original_amount and
# debit_credit (S/H mapped to the English D/C) -- together with the (denormalised)
# account types. The signed
# `amount` (and the offsetting-side `offsetting_amount`) are then STORED GENERATED
# columns derived from those inputs, so they never drift from the raw data and no
# re-import is needed when the derivation changes.
#
# Identity / re-import: each booking carries the DATEV "Buchungs GUID" (field 103,
# a stable per-booking key that DATEV keeps for the booking's whole life). The
# DTVF importer upserts on it -- known GUID => UPDATE, new GUID => INSERT -- so no
# soft-delete / replaces bookkeeping is needed. Every booking optionally points to
# the datev_booking_batches row (the Buchungsstapel / Primanota it came from).

class AddDatevBookings < ActiveRecord::Migration[7.1]
  def change
    create_datev_booking_batches
    create_datev_bookings
  end

  private

  # One row per DATEV Buchungsstapel (= one Primanota = one DTVF export file).
  # Populated from the DTVF header line (fields named below); identified by the
  # header's stable coordinates (see the unique index).
  def create_datev_booking_batches
    create_table "datev_booking_batches", id: :bigserial, force: :cascade do |t|
      t.datetime "created_at", null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime "updated_at", null: true

      # --- Identity (the stable header coordinates of the Stapel) ---
      t.string :consultant_number, null: false, comment: "DATEV Berater-Nr (Header-Feld 11)"
      t.string :client_number, null: false, comment: "DATEV Mandanten-Nr (Header-Feld 12)"
      t.date :period_from, null: false,
        comment: "DATEV 'Datum von' (Header-Feld 15): Beginn des Stapel-Zeitraums"
      t.date :period_to, null: false,
        comment: "DATEV 'Datum bis' (Header-Feld 16): Ende des Zeitraums; Monat+Jahr bilden die Primanota-/Stapelnummer"
      t.string :label, null: false,
        comment: "DATEV 'Bezeichnung' (Header-Feld 17), z. B. 'Einzüge Januar 2026'"

      # --- Derived / provenance ---
      t.integer :fiscal_year, null: true, comment: "Geschäftsjahr (Jahr aus WJ-Beginn, Header-Feld 13)"
      t.date :fiscal_year_start, null: true, comment: "DATEV 'WJ-Beginn' (Header-Feld 13)"
      t.string :primanota_number, null: true,
        comment: "Rekonstruierte Primanota-/Stapelnummer 'MM-YYYY/NNNN' (Monat aus period_to + laufende Nr im Export); Anzeigewert, kein Identitätsschlüssel"

      # --- Further header fields ---
      t.string :origin_indicator, null: true, comment: "DATEV 'Herkunft' (Header-Feld 8), z. B. RE/SV"
      t.boolean :festschreibung, null: false, default: false,
        comment: "DATEV Festschreibung (Header-Feld 21): true = Stapel unveränderlich (GoBD)"
      t.integer :booking_type, null: true, comment: "DATEV Buchungstyp (Header-Feld 19): 1 = Finanzbuchführung"
      t.integer :account_number_length, null: true, comment: "DATEV Sachkontenlänge (Header-Feld 14)"
      t.string :chart_of_accounts, null: true, comment: "DATEV Sachkontenrahmen / SKR (Header-Feld 27), z. B. '42'"
      t.string :currency, null: false, default: "EUR", comment: "DATEV Basiswährung WKZ (Header-Feld 22)"
      t.datetime :datev_created_at, null: true,
        comment: "DATEV 'Erzeugt am' (Header-Feld 6); gespeichert, aber NICHT als verlässliches Änderungssignal genutzt"

      t.string :source_file, null: true, comment: "Dateiname der DTVF-Datei"
      t.integer :file_sequence, null: true, comment: "_NNNNN-Sequenz im Dateinamen des Exports"

      t.jsonb :header_raw, null: false, default: {},
        comment: "Alle 31 Header-Felder roh (inkl. der undokumentierten Felder 24/26), zur Nachvollziehbarkeit"

      # Header fields with a value but no dedicated column yet (mirrors
      # datev_bookings.other_datev_fields). Catches anything DATEV adds to the
      # Stapel header that we do not model explicitly. Default empty.
      t.jsonb :other_datev_fields, null: false, default: {},
        comment: "Header-Felder mit Wert ohne eigene Spalte; fängt sonst nicht abgebildete Headerangaben ab"
    end

    # A Buchungsstapel is uniquely identified by Berater + Mandant + Zeitraum
    # (Datum von/bis) + Bezeichnung. These are stable across re-exports of the
    # same Stapel; the file sequence and the reconstructed Primanota number are
    # not (they depend on the export as a whole), so they are NOT part of the key.
    add_index :datev_booking_batches,
      [:consultant_number, :client_number, :period_from, :period_to, :label],
      unique: true, name: "index_datev_booking_batches_on_identity"
  end

  def create_datev_bookings
    create_table "datev_bookings", id: :bigserial, force: :cascade do |t|
      t.datetime "created_at", null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime "updated_at", null: true

      t.string :account_number, null: false, comment: "DATEV Konto"
      t.string :offsetting_account_number, null: false, comment: "DATEV Gegenkonto"

      t.string :original_account_number, null: true, comment: "Original DATEV Konto if mapped on import"
      t.string :original_offsetting_account_number, null: true, comment: "Original DATEV Gegenkonto if mapped on import"

      # Account type (DATEV Kontenart), denormalised from
      # wsjrdp_ledger_accounts to be available without a JOIN.  Drives
      # the generated amount signs.
      t.string :account_type, null: false, comment: "DATEV Kontenart of account_number"
      t.string :offsetting_account_type, null: false, comment: "DATEV Kontenart of offsetting_account_number"

      # Polymorphic target classes for the `account` and
      # `offsetting_account` associations: personal-account legs (creditors,
      # future debitors) resolve to WsjrdpPersonalAccount, everything else to
      # WsjrdpLedgerAccount.
      t.virtual :account_ref_type, type: :string, stored: true,
        as: "CASE WHEN account_type IN ('CREDITOR', 'DEBITOR') THEN 'WsjrdpPersonalAccount' ELSE 'WsjrdpLedgerAccount' END",
        comment: "Target class of the polymorphic `account` association"
      t.virtual :offsetting_account_ref_type, type: :string, stored: true,
        as: "CASE WHEN offsetting_account_type IN ('CREDITOR', 'DEBITOR') THEN 'WsjrdpPersonalAccount' ELSE 'WsjrdpLedgerAccount' END",
        comment: "Target class of the polymorphic `offsetting_account` association"

      # Amount family (2 currencies x {absolute, signed Konto, signed Gegenkonto}).
      # Accounting is kept in the base currency (EUR). absolute_base_amount is the
      # sign-less base-currency amount -- the DATEV Basis-Umsatz for a
      # foreign-currency booking, otherwise the Umsatz itself. The signed ledger
      # columns (amount, offsetting_amount) derive from it, so every ledger sum is
      # in EUR. The transaction-currency figures (absolute_transaction_amount and
      # its signed transaction_amount / offsetting_transaction_amount) are always
      # stored too; they only differ from the base ones for foreign-currency rows.
      t.decimal :absolute_base_amount, precision: 20, scale: 3, null: false,
        comment: "Vorzeichenloser Buchungsbetrag in Basiswährung (EUR): DATEV Basis-Umsatz bei Fremdwährung, sonst der Umsatz"
      t.string :debit_credit, null: false,
        comment: "Debit/Credit indicator: 'D' = Debit, 'C' = Credit, derived from DATEV S/H"
      t.string :base_currency, null: false, default: "EUR",
        comment: "Basis-/Buchungswährung (EUR): DATEV WKZ Basis-Umsatz bei Fremdwährung, sonst WKZ Umsatz"
      t.virtual :amount, type: :decimal, precision: 20, scale: 3, stored: true,
        as: "absolute_base_amount " \
          "* (CASE WHEN debit_credit = 'C' THEN -1 ELSE 1 END) " \
          "* (CASE WHEN account_type IN ('INCOME', 'EXPENSE') THEN -1 ELSE 1 END)",
        comment: "Signed booking value in the base currency (EUR) from the account (Konto) perspective (incoming +, outgoing -)"
      t.virtual :offsetting_amount, type: :decimal, precision: 20, scale: 3, stored: true,
        as: "-absolute_base_amount " \
          "* (CASE WHEN debit_credit = 'C' THEN -1 ELSE 1 END) " \
          "* (CASE WHEN offsetting_account_type IN ('INCOME', 'EXPENSE') THEN -1 ELSE 1 END)",
        comment: "Signed booking value in the base currency (EUR) from the offsetting (Gegenkonto) perspective, same sign convention as amount"

      t.string :description, null: true,
        comment: "Display/working text; initially copied from original_posting_text (with mojibake repair for the " \
          "2025 KOST1=9500/Konto=1200 batch), then hand-editable and left untouched on re-import"

      t.string :cost_center_number, null: true, comment: "DATEV KOST1 (year <= 2025) or KOST2 (year >= 2026)"
      t.string :sphere_number, null: true, comment: "Tax sphere (steuerliche Sphäre). Year >=2026 (SKR42) from DATEV KOST1; year <=2025 defaults to 3 (Zweckbetrieb)"
      t.string :original_kost1, null: true, comment: "DATEV KOST1"
      t.string :original_kost2, null: true, comment: "DATEV KOST2"

      t.string :document_field_1, null: true, comment: "DATEV Belegfeld 1"
      t.string :document_field_2, null: true, comment: "DATEV Belegfeld 2"

      t.date :booking_date, null: true, comment: "DATEV Datum" # Claude:: Can this be NULL is real data?
      t.date :service_date, null: true, comment: "DATEV Leistungsdatum"

      t.string :original_posting_text, null: true, comment: "DATEV Buchungstext"
      t.string :origin_indicator, null: true,
        comment: 'DATEV "HK" (origin indicator), e.g. SV (batch processing) or RE (accounting)'

      # As-booked transaction-currency figures. absolute_transaction_amount is the
      # DATEV Umsatz (always stored -- for an EUR booking it equals
      # absolute_base_amount). transaction_amount / offsetting_transaction_amount
      # are its signed Konto / Gegenkonto values, mirroring amount /
      # offsetting_amount but in the transaction currency. They differ from the
      # base-currency columns only when transaction_currency != base_currency.
      t.decimal :absolute_transaction_amount, precision: 20, scale: 3, null: false,
        comment: "DATEV Umsatz (Feld 1, vorzeichenlos) in Transaktionswährung; für EUR-Buchungen = absolute_base_amount"
      t.string :transaction_currency, null: false, default: "EUR",
        comment: "DATEV WKZ Umsatz (Feld 3): Transaktionswährung, in der die Buchung erfasst wurde (EUR für die Mehrheit, sonst z. B. PLN)"
      t.virtual :transaction_amount, type: :decimal, precision: 20, scale: 3, stored: true,
        as: "absolute_transaction_amount " \
          "* (CASE WHEN debit_credit = 'C' THEN -1 ELSE 1 END) " \
          "* (CASE WHEN account_type IN ('INCOME', 'EXPENSE') THEN -1 ELSE 1 END)",
        comment: "Signed booking value in the transaction currency from the account (Konto) perspective"
      t.virtual :offsetting_transaction_amount, type: :decimal, precision: 20, scale: 3, stored: true,
        as: "-absolute_transaction_amount " \
          "* (CASE WHEN debit_credit = 'C' THEN -1 ELSE 1 END) " \
          "* (CASE WHEN offsetting_account_type IN ('INCOME', 'EXPENSE') THEN -1 ELSE 1 END)",
        comment: "Signed booking value in the transaction currency from the offsetting (Gegenkonto) perspective"
      t.decimal :exchange_rate, precision: 11, scale: 6, null: true,
        comment: "DATEV Kurs (Feld 4): angegebener Umrechnungskurs; nur bei Fremdwährung"

      # DATEV Beleglink (Feld 20) points at the document image in DATEV
      # Unternehmen online as `BEDI "<guid>"`. We keep only the GUID (the raw
      # Beleglink also stays in other_datev_fields). Nullable: most bookings
      # carry no document link. Stored as string (not uuid) so DATEV's original
      # upper-case spelling is preserved verbatim.
      t.string :bedi_guid, null: true,
        comment: 'DATEV Beleglink BEDI-GUID (Feld 20, aus BEDI "<guid>"): Verweis auf das Belegbild in DATEV Unternehmen online (Original-Schreibweise)'

      # DATEV Beleginfo (Felder 21-36: 8 Art/Inhalt-Paare) and Zusatzinformation
      # (Felder 48-87: 20 Art/Inhalt-Paare) as ordered arrays of
      # {num, key, value} -- num is the DATEV slot (1..8 / 1..20), key the "Art",
      # value the "Inhalt". Only populated slots are stored (gaps allowed); slot
      # number and DTVF order are preserved. Queried by key via `@> '[{"key":..}]'`
      # (GIN-indexed below).
      t.jsonb :beleginfo, null: false, default: [],
        comment: 'DATEV Beleginfo (Felder 21-36) als [{num,key,value}]; num = Slot, key = Art, value = Inhalt'
      t.jsonb :zusatzinformation, null: false, default: [],
        comment: 'DATEV Zusatzinformation (Felder 48-87) als [{num,key,value}]; num = Slot, key = Art, value = Inhalt'

      # ==== Non-DATEV data

      t.string :secondary_cost_center_number, null: true, comment: "Manually maintained secondary cost center. Not from DATEV"

      # ==== References

      t.references :accounting_entry, null: true, foreign_key: true, index: {unique: true},
        comment: "Optional 1:1 (<-> accounting_entries)"
      # accounting_entry_link_type: HOW the booking was linked to its
      # accounting_entry. Deliberately a Ruby comment, NOT a DB comment -- the set
      # of values keeps changing and we don't want a migration per change. The
      # same two import-equivalent types are stamped by BOTH the DATEV importer
      # and a UI connect (DatevBookingMatcher.detect_link_type), so they drive the
      # :automatic rating tier either way. See doc/recon_linking.md.
      # Values set right now:
      #   "2025_fee_booking"                  -- 2025 fee rule: person id (role
      #                                          prefix) in the text + Valuta on
      #                                          the booking date
      #   "document_field_1_pre_notification" -- Einzug Belegfeld 1 -> pre-notification id
      #   nil                                 -- a heuristic / genuinely manual
      #                                          link (matched neither rule); its
      #                                          quality is rated on the fly
      # accounting_entry_linked_at / accounting_entry_link_person_id: when and by
      # whom the link was made -- person 1 (system) for the importer, the acting
      # user for a UI connect.
      t.string :accounting_entry_link_type, null: true
      t.datetime :accounting_entry_linked_at, null: true
      t.bigint :accounting_entry_link_person_id, null: true
      t.references :person, null: true, foreign_key: true,
        comment: "Optional n:1 (<-> people)"
      t.references :camt_transaction, null: true,
        foreign_key: {to_table: :wsjrdp_camt_transactions},
        comment: "Optional 1:1 (<-> wsjrdp_camt_transactions)"

      # The Buchungsstapel (Primanota) this booking was imported from. Optional:
      # a booking need not (yet) be linked to a batch, and the batch is imported
      # from the same DTVF header, so the FK stays nullable.
      t.references :datev_booking_batch, null: true, foreign_key: true,
        comment: "Optional n:1 (<-> datev_booking_batches): der Buchungsstapel/Primanota dieser Buchung"

      # --- Raw booking inputs (from the DATEV Primanota columns) ---

      # DATEV "Buchungs GUID" (Feld 103): assigned by DATEV Rechnungswesen at the
      # booking's first entry and kept unchanged for its whole life (also across
      # edits). The stable, unique key the DTVF importer upserts on. NOT NULL and
      # unique -- every imported booking must carry one (the fake-DTVF generator
      # for 2025 supplies a deterministic UUIDv5).
      t.uuid :buchungs_guid, null: false,
        comment: "DATEV Buchungs GUID (Feld 103): stabiler, eindeutiger Schlüssel je Buchung; Basis für Upsert beim Re-Import"

      # --- Provenance: which DATEV export / Primanota this row came from ---

      t.string :consultant_number, null: true,
        comment: "DATEV consultant number from the Primanota header"
      t.string :client_number, null: true,
        comment: "DATEV client number from the Primanota header"
      t.integer :fiscal_year, null: true,
        comment: "Fiscal year of the export (e.g. 2025)"
      t.date :primanota_period, null: true,
        comment: "First day of the booking month of the Primanota (from the header, e.g. 2026-04-01)"
      t.string :primanota_number, null: true,
        comment: 'DATEV Primanota number from the header (e.g. "08-2025/0001")'
      t.string :primanota_label, null: true,
        comment: 'Primanota label from the header (e.g. "Einzuege August 2025")'
      t.string :source_file, null: true,
        comment: "Original DATEV export file (file name)"
      t.string :source_sheet, null: true,
        comment: 'Original worksheet in the export (e.g. "Primanota 08-2025_0001")'

      # Any DTVF record field that carries a value but has no dedicated column
      # yet (e.g. Beleglink, Beleginfo, Zusatzinformation, Festschreibung,
      # Generalumkehr, Kurs/Basis-Umsatz). Also catches DTVF fields that are
      # normally empty for us, should DATEV ever populate them -- so no exported
      # information is silently dropped. Default empty.
      t.jsonb :other_datev_fields, null: false, default: {},
        comment: "DTVF-Satzfelder mit Wert ohne eigene Spalte (z. B. Beleglink-Rohwert, Festschreibung, Generalumkehr, Kurs, Basis-Umsatz); fängt auch sonst leere Felder ab"

      t.jsonb :additional_info, null: false, default: {},
        comment: "Reserved for our own, non-DATEV extension data (JSONB). Empty by default."

      # Adds created_at + updated_at (datetime, null: false); Rails maintains them
      # automatically (the importer sets both explicitly on insert/update).
    end

    # Upsert key of the DTVF importer: the DATEV Buchungs GUID uniquely and
    # stably identifies a booking across exports.
    add_index :datev_bookings, [:buchungs_guid], unique: true,
      name: "index_datev_bookings_on_buchungs_guid"

    # Supports locating a booking within its source Primanota (display / lookup).
    add_index :datev_bookings,
      [:consultant_number, :client_number, :fiscal_year, :primanota_number],
      name: "index_datev_bookings_on_source"

    # Supports listing/aggregating the bookings of a Primanota period.
    add_index :datev_bookings, [:primanota_period], name: "index_datev_bookings_on_period"

    # Look up bookings by their DATEV document link (Belegbild).
    add_index :datev_bookings, [:bedi_guid], name: "index_datev_bookings_on_bedi_guid"

    # Containment search over the Beleginfo / Zusatzinformation arrays, e.g.
    #   WHERE beleginfo @> '[{"key":"Rechnungsnummer"}]'
    # jsonb_path_ops keeps the GIN index small and fast for @> queries.
    add_index :datev_bookings, :beleginfo, using: :gin, opclass: :jsonb_path_ops,
      name: "index_datev_bookings_on_beleginfo"
    add_index :datev_bookings, :zusatzinformation, using: :gin, opclass: :jsonb_path_ops,
      name: "index_datev_bookings_on_zusatzinformation"
  end
end
