# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Bookings from DATEV Buchungsstapel (Primanota) exports.
#
# The DATEV export only carries sign-less transaction volumes (Umsatz
# or Basis-Umsatz) plus a debit/credit (S/H) flag. The (signed)
# `amount` and `signed_offsetting_base_amount` columns in this table are
# generated.  The sign is computed based on `debit_credit` and
# `account_kind` or `offsetting_account_kind`.
#
# Identity / re-import: each booking carries the DATEV Buchungs GUID
# (field 103, a stable per-booking key that DATEV keeps for the
# booking's whole life). The DTVF importer upserts on it (plan/apply:
# known GUID => UPDATE of the changed columns, new GUID => INSERT).
# Every booking optionally points to the datev_booking_batches row
# (the Buchungsstapel / Primanota it came from).
#
# Comment policy: a DB comment only where it adds information beyond
# the column name -- typically the DATEV source field (named without
# quotes) and its header/record field number.

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
    create_table :datev_booking_batches, id: :bigserial, force: :cascade,
      comment: "DATEV Buchungsstapel (Primanota): one row per batch = one DTVF export file" do |t|
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :updated_at, null: true

      # ---- Identity (the stable header coordinates of the Stapel) ---
      t.string :consultant_number, null: false, comment: "DATEV Berater number (header field 11)"
      t.string :client_number, null: false, comment: "DATEV Mandant number (header field 12)"
      t.date :period_from, null: false, comment: "DATEV Datum von (header field 15): start of the batch period"
      t.date :period_to, null: false, comment: "DATEV Datum bis (header field 16): end of the period; its month + year form the Primanota number"
      t.string :label, null: false, comment: "DATEV Bezeichnung (header field 17), e.g., Einzüge Januar 2026"

      # ---- Derived / provenance ---
      t.date :financial_year_start, null: true, comment: "DATEV WJ-Beginn (header field 13)"
      t.string :primanota_number, null: true,
        comment: "Reconstructed Primanota number MM-YYYY/NNNN (month from period_to + running number within the export); display value, NOT part of the identity"

      # ---- Further header fields ---
      t.datetime :datev_created_at, null: true, comment: "DATEV Erzeugt am (header field 6); stored, but NOT used as a reliable change signal"
      t.string :origin_indicator, null: true, comment: "DATEV Herkunft (header field 8), e.g. RE or SV"
      t.integer :ledger_account_number_length, null: true, comment: "DATEV Sachkontenlänge (header field 14)"
      t.integer :booking_type, null: true, comment: "DATEV Buchungstyp (header field 19): 1 = Finanzbuchführung"
      t.boolean :is_finalized, null: false, default: false, comment: "DATEV Festschreibung (header field 21): true = batch immutable (GoBD)"
      t.string :base_currency, null: false, default: "EUR", comment: "DATEV base currency WKZ (header field 22); EUR enforced by check constraint"
      t.string :datev_chart_of_accounts_number, null: true, comment: "DATEV Sachkontenrahmen / SKR (header field 27), e.g. 42"

      t.string :source_file, null: true, comment: "name of the file we read the Buchungsstapel from"

      t.jsonb :header_raw, null: false, default: {}, comment: "All header fields, keyed by their 1-based DATEV field number (incl. undocumented fields)"

      # ---- Hitobito columns

      t.string :import_export, null: false, comment: "import = reading into Hitobito, export = writing from Hitobito"
      t.text :description, null: false, default: ""
      t.text :comment, null: false, default: ""
      t.jsonb :additional_info, null: false, default: {}, comment: "Reserved for future use"

      # The whole bookkeeping assumes the base currency EUR, so lets
      # pin it down.
      t.check_constraint "base_currency = 'EUR'", name: "chk_datev_booking_batch_base_currency"
    end

    # A Buchungsstapel is uniquely identified by Berater + Mandant + Zeitraum
    # (Datum von/bis) + Bezeichnung. These are stable across re-exports of the
    # same Stapel; the file sequence and the reconstructed Primanota number are
    # not (they depend on the export as a whole), so they are NOT part of the key.
    add_index :datev_booking_batches,
      [:consultant_number, :client_number, :period_from, :period_to, :label],
      unique: true, name: "index_datev_booking_batches_on_identity"
  end

  # The closed set of account types (DATEV Kontenart classification): the
  # ACCOUNT_KIND_* constants of the wsjrdp_scripts importer plus DEBITOR for
  # future debitor legs. UNKNOWN is allowed on purpose -- it is the placeholder
  # classification for account ranges we do not model yet.
  ACCOUNT_KINDS_SQL = "('BANK', 'TRANSIT', 'CLEARING', 'LIABILITY', " \
    "'CREDITOR', 'DEBITOR', 'INCOME', 'EXPENSE', 'EQUITY', 'UNKNOWN')"

  def create_datev_bookings
    create_table :datev_bookings, id: :bigserial, force: :cascade,
      comment: "DATEV bookings: one row per booking of the imported Buchungsstapel exports" do |t|
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :updated_at, null: true

      # The Buchungsstapel (Primanota) this booking was imported
      # from. Optional: a booking need not (yet) be linked to a batch,
      # and the batch is imported from the same DTVF header, so the FK
      # stays nullable.
      t.references :datev_booking_batch, null: true, foreign_key: {on_delete: :nullify},
        comment: "Optional n:1 (<-> datev_booking_batches): the Buchungsstapel/Primanota this booking came from"

      # DATEV Buchungs GUID (record field 103): assigned by DATEV
      # Rechnungswesen at the booking's first entry and kept unchanged
      # for its whole life (also across edits). The stable, unique key
      # the DTVF importer upserts on.
      t.uuid :buchungs_guid, null: false,
        comment: "DATEV Buchungs GUID (record field 103): stable, unique per-booking key; upsert key of the importer"

      t.string :account_number, null: false, comment: "DATEV Konto"
      t.string :offsetting_account_number, null: false, comment: "DATEV Gegenkonto"

      t.string :original_account_number, null: true, comment: "Original DATEV Konto if mapped on import"
      t.string :original_offsetting_account_number, null: true, comment: "Original DATEV Gegenkonto if mapped on import"

      # Account type (DATEV Kontenart), denormalised from
      # wsjrdp_ledger_accounts to be available without a JOIN.  Drives
      # the generated amount signs; value set enforced by check constraints.
      t.string :account_kind, null: false, comment: "DATEV Kontenart of account_number"
      t.string :offsetting_account_kind, null: false, comment: "DATEV Kontenart of offsetting_account_number"

      # Polymorphic target classes for the `account` and
      # `offsetting_account` associations: personal-account legs (creditors,
      # future debitors) resolve to WsjrdpPersonalAccount, everything else to
      # WsjrdpLedgerAccount.
      t.virtual :account_type, type: :string, stored: true,
        as: "CASE WHEN account_kind IN ('CREDITOR', 'DEBITOR') THEN 'WsjrdpPersonalAccount' ELSE 'WsjrdpLedgerAccount' END",
        comment: "Target class of the polymorphic `account` association"
      t.virtual :offsetting_account_type, type: :string, stored: true,
        as: "CASE WHEN offsetting_account_kind IN ('CREDITOR', 'DEBITOR') THEN 'WsjrdpPersonalAccount' ELSE 'WsjrdpLedgerAccount' END",
        comment: "Target class of the polymorphic `offsetting_account` association"

      # Amount family (2 currencies x {absolute, signed Konto, signed Gegenkonto}).
      # Accounting is kept in the base currency (EUR). base_amount is the
      # sign-less base-currency amount -- the DATEV Basis-Umsatz for a
      # foreign-currency booking, otherwise the Umsatz itself. The signed ledger
      # columns (signed_base_amount, signed_offsetting_base_amount) derive from it,
      # so every ledger sum is in EUR. The transaction-currency figures (transaction_amount and
      # its signed signed_transaction_amount / signed_offsetting_transaction_amount) are always
      # stored too; they only differ from the base ones for foreign-currency rows.
      t.decimal :base_amount, precision: 20, scale: 3, null: false,
        comment: "Sign-less booking amount in the base currency (EUR): DATEV Basis-Umsatz for foreign-currency bookings, else the Umsatz"
      t.string :debit_credit, null: false,
        comment: "Debit/credit indicator derived from DATEV S/H: D = debit, C = credit"
      t.string :base_currency, null: false, default: "EUR",
        comment: "Base/ledger currency: DATEV WKZ Basis-Umsatz for foreign-currency bookings, else WKZ Umsatz; the importer refuses non-EUR values"
      t.virtual :signed_base_amount, type: :decimal, precision: 20, scale: 3, stored: true,
        as: "base_amount " \
          "* (CASE WHEN debit_credit = 'C' THEN -1 ELSE 1 END) " \
          "* (CASE WHEN account_kind IN ('INCOME', 'EXPENSE') THEN -1 ELSE 1 END)",
        comment: "Signed booking value in the base currency (EUR) from the account (Konto) perspective (incoming +, outgoing -)"
      t.virtual :signed_offsetting_base_amount, type: :decimal, precision: 20, scale: 3, stored: true,
        as: "-base_amount " \
          "* (CASE WHEN debit_credit = 'C' THEN -1 ELSE 1 END) " \
          "* (CASE WHEN offsetting_account_kind IN ('INCOME', 'EXPENSE') THEN -1 ELSE 1 END)",
        comment: "Signed booking value in the base currency (EUR) from the offsetting (Gegenkonto) perspective, same sign convention as signed_base_amount"

      t.string :posting_text, null: true,
        comment: "Display/working posting text; initially copied from original_posting_text (with mojibake repair " \
          "for the 2025 KOST1=9500/Konto=1200 batch), then hand-editable and left untouched on re-import"
      t.string :original_posting_text, null: true, comment: "DATEV Buchungstext"

      t.string :cost_center_number, null: true, comment: "DATEV KOST1 (year <= 2025) or KOST2 (year >= 2026)"
      t.string :sphere_number, null: true, comment: "Tax sphere (steuerliche Sphäre): year >= 2026 (SKR42) from DATEV KOST1; year <= 2025 defaults to 3 (Zweckbetrieb)"
      t.string :original_kost1, null: true, comment: "DATEV KOST1"
      t.string :original_kost2, null: true, comment: "DATEV KOST2"

      t.string :document_field_1, null: true, comment: "DATEV Belegfeld 1"
      t.string :document_field_2, null: true, comment: "DATEV Belegfeld 2"

      t.date :booking_date, null: false, comment: "DATEV Belegdatum"
      t.date :service_date, null: true, comment: "DATEV Leistungsdatum"

      t.boolean :is_finalized, null: false, default: false,
        comment: "DATEV Festschreibung record column: true only when the export explicitly marks the booking festgeschrieben (GoBD); empty/0 -> false"
      t.boolean :is_general_reversal, null: false, default: false,
        comment: "DATEV Generalumkehr (GU) record column: true = reversal posting (exported side-flipped; no extra sign factor needed)"

      # As-booked transaction-currency figures. transaction_amount is the
      # DATEV Umsatz (always stored -- for an EUR booking it equals
      # base_amount). signed_transaction_amount / signed_offsetting_transaction_amount
      # are its signed Konto / Gegenkonto values, mirroring signed_base_amount /
      # signed_offsetting_base_amount but in the transaction currency. They differ from the
      # base-currency columns only when transaction_currency != base_currency.
      t.decimal :transaction_amount, precision: 20, scale: 3, null: false,
        comment: "DATEV Umsatz (record field 1, sign-less) in the transaction currency; equals base_amount for EUR bookings"
      t.string :transaction_currency, null: false, default: "EUR",
        comment: "DATEV WKZ Umsatz (record field 3): currency the booking was entered in (mostly EUR, else e.g. PLN)"
      t.virtual :signed_transaction_amount, type: :decimal, precision: 20, scale: 3, stored: true,
        as: "transaction_amount " \
          "* (CASE WHEN debit_credit = 'C' THEN -1 ELSE 1 END) " \
          "* (CASE WHEN account_kind IN ('INCOME', 'EXPENSE') THEN -1 ELSE 1 END)",
        comment: "Signed booking value in the transaction currency from the account (Konto) perspective"
      t.virtual :signed_offsetting_transaction_amount, type: :decimal, precision: 20, scale: 3, stored: true,
        as: "-transaction_amount " \
          "* (CASE WHEN debit_credit = 'C' THEN -1 ELSE 1 END) " \
          "* (CASE WHEN offsetting_account_kind IN ('INCOME', 'EXPENSE') THEN -1 ELSE 1 END)",
        comment: "Signed booking value in the transaction currency from the offsetting (Gegenkonto) perspective"
      t.decimal :exchange_rate, precision: 28, scale: 12, null: true,
        comment: "DATEV Kurs (record field 4); only present for foreign-currency bookings"

      # DATEV Beleglink (record field 20) points at a document image
      # in DATEV Unternehmen online as BEDI "<guid>". For these links,
      # this column contains just the GUID. The verbatim Beleglink
      # stays in other_datev_columns). Nullable: most bookings carry
      # no document link.
      t.uuid :bedi_guid, null: true,
        comment: "DATEV Beleglink BEDI GUID (record field 20): reference to the document image in DATEV Unternehmen online"

      t.string :origin_indicator, null: true,
        comment: "DATEV Herkunft-Kz (HK), e.g. SV (batch processing) or RE (accounting)"

      # DATEV Beleginfo (record fields 21-36: 8 Art/Inhalt pairs) and
      # Zusatzinformation (record fields 48-87: 20 Art/Inhalt pairs) as ordered
      # arrays of {num, key, value} -- num is the DATEV slot (1..8 / 1..20),
      # key the Art, value the Inhalt. Only populated slots are stored (gaps
      # allowed); slot number and DTVF order are preserved. Queried by key via
      # `@> '[{"key":..}]'` (GIN-indexed below).
      t.jsonb :beleginfo, null: false, default: [],
        comment: "DATEV Beleginfo (record fields 21-36) as [{num,key,value}]; num = slot, key = Art, value = Inhalt"
      t.jsonb :zusatzinformation, null: false, default: [],
        comment: "DATEV Zusatzinformation (record fields 48-87) as [{num,key,value}]; num = slot, key = Art, value = Inhalt"

      # other_datev_columns -- Any DTVF record field that carries a
      # value but has no dedicated column yet (e.g. the raw Beleglink
      # or the BU-Schlüssel). Also catches DTVF fields that are
      # normally empty for us, should DATEV ever populate them -- so
      # no exported information is silently dropped.
      t.jsonb :other_datev_columns, null: false, default: {},
        comment: "DTVF record fields with a value but no dedicated column (e.g. raw Beleglink, BU-Schlüssel)"

      # source_file -- Which Primanota export a booking belongs to
      # lives on the batch (financial_year, period, primanota_number)
      # and is reached through datev_booking_batch_id. As the same
      # Primanota can have a different filename on a later export from
      # DATEV we store the source_file per booking.  stamped on INSERT
      # and on every genuinely CHANGED row, but a re-import that
      # changes nothing (same or re-exported file without changes)
      # never touches it.
      t.string :source_file, null: true, comment: "File of the DTVF import that inserted or last genuinely changed this row"

      # ---- Non-DATEV data

      t.string :secondary_cost_center_number, null: true, comment: "Manually maintained secondary cost center; not from DATEV"
      t.string :sub_cost_center_number, null: true, comment: "Manually maintained sub cost center; not from DATEV"
      t.boolean :is_unit_budget, null: true, comment: "Flag to override automatic logic if a booking belongs to the budget of a unit"
      t.jsonb :additional_info, null: false, default: {}, comment: "Reserved for future use"

      # Value-domain guards, mirroring the master-data tables' check
      # constraints. The account types also back the generated ref_type /
      # amount-sign expressions above.
      t.check_constraint "debit_credit IN ('D', 'C')",
        name: "chk_datev_booking_debit_credit"
      t.check_constraint "account_kind IN #{ACCOUNT_KINDS_SQL}",
        name: "chk_datev_booking_account_kind"
      t.check_constraint "offsetting_account_kind IN #{ACCOUNT_KINDS_SQL}",
        name: "chk_datev_booking_offsetting_account_kind"
    end

    # Upsert key of the DTVF importer: the DATEV Buchungs GUID uniquely and
    # stably identifies a booking across exports.
    add_index :datev_bookings, [:buchungs_guid], unique: true,
      name: "index_datev_bookings_on_buchungs_guid"

    # Look up bookings by their DATEV document link (Belegbild).
    add_index :datev_bookings, [:bedi_guid], name: "index_datev_bookings_on_bedi_guid"

    # Listing/filter paths of the bookkeeping views: the per-account pages
    # query account_number OR offsetting_account_number (two single-column
    # indexes combine via bitmap OR), the CNF filters and default sorts hit
    # cost center / sphere / booking date.
    add_index :datev_bookings, [:account_number],
      name: "index_datev_bookings_on_account_number"
    add_index :datev_bookings, [:offsetting_account_number],
      name: "index_datev_bookings_on_offsetting_account_number"
    add_index :datev_bookings, [:cost_center_number],
      name: "index_datev_bookings_on_cost_center_number"
    add_index :datev_bookings, [:sphere_number],
      name: "index_datev_bookings_on_sphere_number"
    add_index :datev_bookings, [:booking_date],
      name: "index_datev_bookings_on_booking_date"

    # Containment search over the Beleginfo / Zusatzinformation arrays, e.g.
    #   WHERE beleginfo @> '[{"key":"Rechnungsnummer"}]'
    # jsonb_path_ops keeps the GIN index small and fast for @> queries.
    add_index :datev_bookings, :beleginfo, using: :gin, opclass: :jsonb_path_ops,
      name: "index_datev_bookings_on_beleginfo"
    add_index :datev_bookings, :zusatzinformation, using: :gin, opclass: :jsonb_path_ops,
      name: "index_datev_bookings_on_zusatzinformation"
  end
end
