# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Moss **card transactions** (Kartentransaktionen), imported from the Moss
# Custom-CSV "WSJ27" export of the "Transaction" format (94 columns; see
# doc/moss_data_model.md 5.2). Column names use the Moss field-reference names in
# snake_case; DB comments name the source field.
#
# Two tables (a Moss card transaction may be SPLIT across several expense
# accounts -- one CSV row per split, sharing the same `Transaction ID`):
#
#   * moss_card_transactions          -- one row per `Transaction ID`. Holds the
#     fields that are IDENTICAL across all splits of a transaction (dates,
#     merchant, cardholder, card, supplier, totals, currency, invoice, ...).
#   * moss_card_transaction_bookings  -- one row per split. Holds the fields that
#     DIFFER between splits (line amounts, expense account, cost center / sphere,
#     description = per-booking Buchungstext, distribution,
#     unique_item_number/sub_row_number). Each row references its transaction via
#     the natural key `card_transaction_uuid` (NOT NULL).
#   The transaction/booking split was determined empirically from the split rows
#   in the WSJ27 sample; the always-0/constant VAT/fee columns stayed on the
#   transaction (no per-split difference in the data) -- revisit if real VAT/fees
#   ever appear per line.
#
# Column policy (see doc 5.2.7): CSV columns >30% filled get a dedicated column;
# columns >70% empty go into the `other_columns` jsonb (only when a value is
# present). Both tables also carry the usual `additional_info` jsonb (our own,
# non-Moss data). Ignored/derived/not-exported columns: see doc 5.2.7.
#
# Naming rule: an id that is a Moss UUID (not a SQL primary key) uses a `_uuid`
# suffix and stays type `string` -> `card_transaction_uuid` (the transaction's
# natural key; bookings reference it directly, no surrogate FK).
#
# DATEV link (see doc 5.2.5): productive Moss->DATEV ("DATEV Unternehmen Online")
# posts a 3-step chain; per Moss booking there are TWO per-booking DATEV bookings
# -- step 1 (Sachkonto -> Sammelkreditor 700002, the receipt/expense booking) and
# step 2 (Sammelkreditor 700002 -> Moss-Konto 36100, the clearing booking). Each
# moss_card_transaction_booking may reference them 1:1 via
# `expense_datev_booking_id` / `clearing_datev_booking_id` (unique).

class AddMossCardTransactions < ActiveRecord::Migration[7.1]
  def change
    create_moss_card_transactions
    create_moss_card_transaction_bookings
  end

  private

  # One row per Moss `Transaction ID`: the fields identical across all splits.
  def create_moss_card_transactions
    create_table "moss_card_transactions", id: :bigserial, force: :cascade do |t|
      t.datetime "created_at", null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime "updated_at", null: true

      # --- Hitobito side ---
      t.bigint "person_id", null: true, comment: "Optionaler Verweis auf people (zugeordnete Person / Karteninhaber)"
      t.bigint "fin_account_id", null: true, comment: "FinAccount des Kartenkontos; noch nicht verdrahtet"
      t.text "comment", default: "", null: false, comment: "Manuelle Notiz (nicht aus Moss), beim Import bewahrt"
      t.string "status", null: true, comment: "Manueller Status (nicht aus Moss), beim Import bewahrt"
      t.jsonb "additional_info", default: {}, null: false,
        comment: "Eigene, nicht-Moss Erweiterungsdaten (JSONB). Standard leer."
      t.jsonb "other_columns", default: {}, null: false,
        comment: "Transaktions-Level WSJ27-Spalten ohne eigene Spalte (>70% leer), nur befüllt wenn vorhanden: Record Type, Supplier IBAN/BIC/Vat ID, VAT Code/Name/Rate, Card Acceptor Name, Client Number, Airline Ticket Number, Number of Months in Release Plan, Prepayment Start/End Date. Zusätzlich moss_record_url / moss_attachment_url / transaction_id_pdf_filename NUR, wenn NICHT aus card_transaction_uuid ableitbar (Model liefert sonst den abgeleiteten Wert)."

      # --- Moss identity ---
      t.string "card_transaction_uuid", null: false,
        comment: "Moss 'Transaction ID' (UUID). Eindeutig je Transaktion; natürlicher Schlüssel (bookings verweisen darüber). = Dateiname in attachments/<uuid>.pdf"
      t.string "transaction_state", null: true, comment: "Moss 'Transaction State' / Transaktionsstatus (z. B. ACCEPTED)"
      t.string "transaction_type", null: true, comment: "Moss 'Transaction Type' (STANDARD/CREDIT)"
      t.string "general_transaction_type", null: true, comment: "Moss 'General Transaction Type' (STANDARD/CREDIT)"
      t.string "is_prepayment", null: true, comment: "Moss 'Is Prepayment?' (Flag, hier durchgehend '0')"

      # --- Dates ---
      t.date "payment_date", null: true, comment: "Moss 'Payment Date' / Zahlungsdatum (Kartenbelastung). Period = YYYY-MM hiervon."
      t.date "booking_date", null: true, comment: "Moss 'Booking Date' / Buchungsdatum"
      t.date "settlement_date", null: true, comment: "Moss 'Settlement Date' / Abrechnungsdatum"
      t.date "first_export_date", null: true, comment: "Moss 'First Export Date'"
      t.date "last_export_date", null: true, comment: "Moss 'Last Export Date'"
      t.date "receipt_date", null: true, comment: "Moss 'Receipt Date' / Belegdatum"
      t.date "service_date", null: true, comment: "Moss 'Service Date' / Leistungsdatum (teils leer)"
      t.date "approval_date", null: true, comment: "Moss 'Approval Date' / Freigabedatum"

      # --- Amounts & currency (transaction level: totals, currency, rates, fees/VAT) ---
      t.decimal "total_amount", precision: 20, scale: 3, null: true, comment: "Moss 'Total Amount' (Gesamttransaktion; Summe der Split-Beträge)"
      t.decimal "total_amount_excl_vat", precision: 20, scale: 3, null: true, comment: "Moss 'Total Amount (excl. VAT)'"
      t.decimal "total_original_amount", precision: 20, scale: 3, null: true, comment: "Moss 'Total Original Amount'"
      t.decimal "total_original_amount_excl_vat", precision: 20, scale: 3, null: true, comment: "Moss 'Total Original Amount (excl. VAT)'"
      t.decimal "vat_amount", precision: 20, scale: 3, null: true, comment: "Moss 'VAT Amount' (im Sample 0; ggf. per Split -> bookings verschieben)"
      t.decimal "original_vat", precision: 20, scale: 3, null: true, comment: "Moss 'Original VAT' (im Sample 0)"
      t.decimal "fees_amount", precision: 20, scale: 3, null: true, comment: "Moss 'Fees Amount' (im Sample 0)"
      t.string "currency", null: false, comment: "Moss 'Currency' / Buchungswährung"
      t.string "home_currency", null: true, comment: "Moss 'Home Currency' (Basiswährung, hier EUR)"
      t.string "original_currency", null: true, comment: "Moss 'Original Currency'"
      t.decimal "conversion_rate", precision: 20, scale: 8, null: true, comment: "Moss 'Conversion Rate' / Wechselkurs"
      t.decimal "conversion_rate_including_fees", precision: 20, scale: 8, null: true, comment: "Moss 'Conversion Rate Including Fees'"

      # --- Merchant & supplier ---
      t.string "merchant_name", null: true, comment: "Moss 'Merchant Name' / Händlername"
      t.string "merchant_city", null: true, comment: "Moss 'Merchant City'"
      t.string "merchant_country", null: true, comment: "Moss 'Merchant Country'"
      t.string "supplier_name", null: true, comment: "Moss 'Supplier Name' (bei Karten: Sammelkreditor, konstant 'Default Moss Supplier')"
      t.string "supplier_account", null: true, comment: "Moss 'Supplier Account' / Lieferantenkonto (Sammelkreditor, 700002)"

      # --- Accounting (transaction level; Kostenstelle/Sphäre sind buchungs-spezifisch -> bookings) ---
      t.string "moss_balance_account", null: true, comment: "Moss 'Moss Balance Account' / Moss-Bilanzkonto (36100)"
      t.string "cash_in_transit_account", null: true, comment: "Moss 'Cash in Transit Account' / Geldtransitkonto (13720)"

      # --- Card & employee ---
      t.string "cardholder", null: true, comment: "Moss 'Cardholder' / Kreditkarteninhaber (voller Name)"
      t.string "card_used", null: true, comment: "Moss 'Card Used' (z. B. 'VIRTUAL - 2557'; letzte 4 Kartenziffern)"
      t.string "card_holder_name", null: true, comment: "Moss 'Card Holder Name'"
      t.string "card_holder_label", null: true, comment: "Moss 'Card Holder Label' (konstant 'Kreditkarteninhaber')"
      t.string "card_label", null: true, comment: "Moss 'Card Label' (konstant 'Kreditkarte')"
      t.string "card_purpose", null: true, comment: "Moss 'Card Purpose'"
      t.string "team_name", null: true, comment: "Moss 'Team Name' / Teamname"
      t.string "approver_name", null: true, comment: "Moss 'Approver Name'"
      t.string "post_spend_approval_status", null: true, comment: "Moss 'Post Spend Approval Status' (APPROVED/NA)"

      # --- Text / links / references ---
      t.string "reason_for_purchase", null: true, comment: "Moss 'Reason for Purchase' / Grund des Einkaufs"
      t.string "parent_booking_text", null: true, comment: "Moss 'Parent Booking Text': Buchungstext der Gesamt-Transaktion (der Buchungstext je Buchung steht in bookings.description; nicht deckungsgleich mit dem DATEV-Buchungstext)"
      t.string "invoice_number", null: true,
        comment: "Moss 'Invoice Number' = DATEV 'Belegfeld 1'. Brücke zu datev_bookings.document_field_1 (Schritt-1-Buchung EXPENSE -> Sammelkreditor 700002)."
      t.string "invoice_file_name", null: true,
        comment: "Moss 'Invoice File Name': Beleg-Dateinamen (mehrere Pipe-getrennt); = Dateien in receipts/"
      t.string "sage_payment_type", null: true, comment: "Moss 'Sage Payment Type' (PA/PR)"
      t.string "sage_transaction_type", null: true, comment: "Moss 'Sage Transaction Type' (PI/PC)"

      t.index ["card_transaction_uuid"], name: "index_moss_card_transactions_uuid", unique: true
      t.index ["invoice_number"], name: "index_moss_card_transactions_invoice_number"
      t.index ["person_id"], name: "index_moss_card_transactions_person_id"
      # Listing/filter performance (default sort + common CNF filters), see
      # MossCardTransactionsQuery / MossCardTransactionsFilter.
      t.index ["booking_date"], name: "index_moss_card_transactions_booking_date"
      t.index ["payment_date"], name: "index_moss_card_transactions_payment_date"
      t.index ["total_amount"], name: "index_moss_card_transactions_total_amount"
      t.index ["transaction_state"], name: "index_moss_card_transactions_transaction_state"
      t.index ["cardholder"], name: "index_moss_card_transactions_cardholder"
    end
  end

  # One row per split of a Moss card transaction: the fields that differ per split.
  def create_moss_card_transaction_bookings
    create_table "moss_card_transaction_bookings", id: :bigserial, force: :cascade do |t|
      t.datetime "created_at", null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime "updated_at", null: true


      # --- Row keys ---
      t.string "unique_item_number", null: true,
        comment: "Moss 'Unique Item Number' (WSJ27): eindeutiger Zeilen-/Buchungsschlüssel."
      t.integer "sub_row_number", default: 0, null: false,
        comment: "Moss 'Sub-row Number': Split-Position innerhalb der Transaktion (WSJ27 1-basiert)."

      t.string "card_transaction_uuid", null: false,
        comment: "Pflicht-Verweis auf moss_card_transactions.card_transaction_uuid (natürlicher Schlüssel; die Transaktion dieser Buchung)"

      # Two per-booking DATEV bookings (see header): strict 1:1 each, optional.
      t.bigint "expense_datev_booking_id", null: true,
        comment: "1:1 -> datev_bookings: Schritt-1-Buchung Sachkonto -> Sammelkreditor 700002 (Beleg/Aufwand)"
      t.bigint "clearing_datev_booking_id", null: true,
        comment: "1:1 -> datev_bookings: Schritt-2-Buchung Sammelkreditor 700002 -> Moss-Konto 36100 (Kreditorenausgleich)"

      t.jsonb "other_columns", default: {}, null: false,
        comment: "Buchungs-Level WSJ27-Spalten ohne eigene Spalte (>70% leer), nur befüllt wenn vorhanden: Unit Price, Quantity."

      # --- Amounts (per split/line) ---
      t.decimal "amount", precision: 20, scale: 3, null: false, comment: "Moss 'Amount' / Betrag dieser Buchung (Zeile)"
      t.decimal "amount_excl_vat", precision: 20, scale: 3, null: true, comment: "Moss 'Amount (excl. VAT)'"
      t.decimal "home_amount", precision: 20, scale: 3, null: true,
        comment: "Moss 'Home Amount' (Basiswährung EUR). Abstimmungs-Anker gegen datev_bookings.absolute_base_amount (These)."
      t.decimal "original_amount", precision: 20, scale: 3, null: true, comment: "Moss 'Original Amount'"
      t.decimal "original_amount_excl_vat", precision: 20, scale: 3, null: true, comment: "Moss 'Original Amount (excl. VAT)'"
      t.decimal "transaction_amount_excluding_fees", precision: 20, scale: 3, null: true, comment: "Moss 'Transaction Amount Excluding Fees'"

      # --- Accounting (per split) ---
      t.string "account_number", null: true, comment: "Moss 'Account Number' / Sachkonto dieser Buchung"
      t.string "name_of_expense_account", null: true, comment: "Moss 'Name of Expense Account'"
      t.string "original_expense_account", null: true, comment: "Moss 'Original Expense Account'"
      t.string "cost_center_number", null: true, comment: "Moss 'Cost Center - Number' dieser Buchung (Link zu wsjrdp_cost_centers; = DATEV KOST1). 'Cost Center - Name' ignoriert."
      t.string "sphere_number", null: true, comment: "Moss 'Cost Carrier - Number' = steuerliche Sphäre dieser Buchung (fix meist 3 = Zweckbetrieb). 'Cost Carrier - Name' ignoriert."
      t.string "distribution_combination", null: true, comment: "Moss 'Distribution combination'"
      t.string "description", default: "", null: false, comment: "Moss 'Note' = Buchungstext dieser Buchung"

      t.jsonb "additional_info", default: {}, null: false,
        comment: "Eigene, nicht-Moss Erweiterungsdaten (JSONB). Standard leer."

      t.index ["unique_item_number"], name: "index_moss_card_transaction_bookings_unique_item_number", unique: true
      t.index ["card_transaction_uuid", "sub_row_number"], name: "index_moss_card_transaction_bookings_uuid_sub_row", unique: true
      t.index ["expense_datev_booking_id"], name: "index_moss_card_transaction_bookings_expense_datev", unique: true
      t.index ["clearing_datev_booking_id"], name: "index_moss_card_transaction_bookings_clearing_datev", unique: true
      # Booking-level CNF filters (Sachkonto / Kostenstelle / Betrag), matched via
      # the LEFT JOIN in MossCardTransactionsFilter.
      t.index ["account_number"], name: "index_moss_card_transaction_bookings_account_number"
      t.index ["cost_center_number"], name: "index_moss_card_transaction_bookings_cost_center_number"
      t.index ["amount"], name: "index_moss_card_transaction_bookings_amount"
    end
  end
end
