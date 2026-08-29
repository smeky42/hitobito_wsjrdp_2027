# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Moss **card transactions** (Kartentransaktionen), imported from a
# Moss Custom-CSV export. Column names usually use the Moss
# field-reference names in snake_case, so a DB comment is only added
# where it says MORE than the column name.
#
# Two tables (a Moss card transaction may be SPLIT across several
# expense accounts -- one CSV row per split, sharing the same
# Transaction ID).
#
# EXCEPTION -- money and currency columns: every amount / currency /
# rate column of the export is ALWAYS mirrored into
# `other_moss_columns` under its verbatim Moss field-reference name
# ("Home Amount", "Total Amount", "Currency", ...), even when a house
# column below carries the same value. The duplication is deliberate
# (source fidelity beats storage): the house columns are derived and
# may be renamed or re-derived, the mirror always shows what Moss
# delivered.
#
# Money house layer (doc/fin/money_conventions.md): these are
# account-perspective tables, so the SIGNED amount is the input (R2: +
# = inflow, a card purchase is negative) and the unsigned amount is
# GENERATED from it -- the mirror image of datev_bookings, where the
# unsigned amount is the input and the signed views are
# generated. `debit_credit` is generated from the sign as well (D =
# purchase, C = refund), matching the S/H of the step-1 DATEV booking
# (verified on the sample: 181 purchases D, 1 refund C).
#
# DATEV link: productive Moss->DATEV ("DATEV Unternehmen Online")
# posts a 3-step chain. The two links sit on DIFFERENT levels, because
# that is how DATEV posts them (verified on the split transactions of
# the sample):
#   * step 1 (Sachkonto -> Sammelkreditor, the receipt/expense
#     booking) exists PER SPLIT ->
#     `moss_card_transaction_bookings.expense_datev_booking_id`
#   * step 2 (Sammelkreditor -> Moss-Konto, the clearing booking)
#     exists ONCE PER TRANSACTION, carrying the transaction total ->
#     `moss_card_transactions.clearing_datev_booking_id`
# Both are 1:1 (unique) and optional.  (Step 3, Moss-Konto ->
# Geldtransit, is a collective settlement)
class AddMossCardTransactions < ActiveRecord::Migration[7.1]
  # Same closed set as datev_bookings (doc/fin/money_conventions.md R5).
  ACCOUNT_KINDS_SQL = "('BANK', 'TRANSIT', 'CLEARING', 'LIABILITY', " \
    "'CREDITOR', 'DEBITOR', 'INCOME', 'EXPENSE', 'EQUITY', 'UNKNOWN')"

  # Polymorphic target class derived from a Kontenart column (R5), NULL when the
  # Kontenart is unknown -- the same expression datev_bookings uses.
  ACCOUNT_TYPE_SQL = lambda do |kind_column|
    "CASE WHEN #{kind_column} IS NULL THEN NULL " \
      "WHEN #{kind_column} IN ('CREDITOR', 'DEBITOR') THEN 'WsjrdpPersonalAccount' " \
      "ELSE 'WsjrdpLedgerAccount' END"
  end

  def change
    create_moss_card_transactions
    create_moss_card_transaction_bookings
  end

  private

  # One row per Moss Transaction ID: the fields identical across all splits.
  def create_moss_card_transactions
    create_table :moss_card_transactions, id: :bigserial, force: :cascade,
      comment: "Moss card transactions: one row per Moss Transaction ID" do |t|
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :updated_at, null: true

      # ---- Moss identity
      t.uuid :card_transaction_uuid, null: false, comment: "CSV Transaction ID"
      t.string :transaction_state, null: true, comment: "e.g., ACCEPTED"
      t.string :transaction_type, null: true, comment: "STANDARD or CREDIT"
      t.string :general_transaction_type, null: true, comment: "STANDARD or CREDIT"
      t.string :is_prepayment, null: true

      # ---- DATEV clearing link (step 2, one per transaction; see header)
      t.bigint :clearing_datev_booking_id, null: true,
        comment: "Optional 1:1 (<-> datev_bookings)"
      t.jsonb :clearing_datev_booking_link_meta, default: {}, null: false

      # ---- Dates
      t.date :payment_date, null: true, comment: "Card charge date; the Moss period (YYYY-MM) derives from it"
      t.date :booking_date, null: true
      t.date :settlement_date, null: true
      t.date :first_export_date, null: true
      t.date :last_export_date, null: true
      t.date :receipt_date, null: true, comment: "Receipt/document date (Belegdatum)"
      t.date :service_date, null: true, comment: "Service date (Leistungsdatum); partly empty"
      t.date :approval_date, null: true

      # ---- Amount (transaction total, base currency)
      # The transaction total in the base currency: signed input (R2), unsigned
      # view generated. The importer computes it as the SUM of the booking lines
      # and verifies it against the Moss "Total Amount" (which equalled the line
      # sum in 181/181 sample transactions, splits included); the Moss totals and
      # every other amount/currency/rate field are mirrored verbatim into
      # other_moss_columns. The transaction currency axis is not stored here --
      # it is SUM(signed_transaction_amount) over the bookings (model method).
      t.decimal :signed_total_base_amount, precision: 20, scale: 3, null: false,
        comment: "Transaction total in the base currency, signed (+ = inflow, i.e. refund); sum of the bookings"
      t.virtual :total_base_amount, type: :decimal, precision: 20, scale: 3, stored: true,
        as: "ABS(signed_total_base_amount)",
        comment: "Sign-less transaction total in the base currency"

      # ---- Merchant & supplier
      t.string :merchant_name, null: true
      t.string :merchant_city, null: true
      t.string :merchant_country, null: true
      t.string :supplier_name, null: true

      # ---- Accounting (transaction level; cost center / sphere are per split -> bookings)
      # The three chain accounts of the Moss->DATEV posting logic. Each carries
      # the same account classification as the booking lines (R5): the Kontenart
      # derived by the importer plus the generated polymorphic target class.
      # In the sample all three are filled on every row (collective creditor
      # 700002 = CREDITOR, Moss account 36100 = CLEARING, cash in transit
      # 13720 = TRANSIT); they stay nullable for rows created outside the import.
      t.string :supplier_account_number, null: true, comment: "CSV Supplier Account"
      t.string :supplier_account_kind, null: true
      t.virtual :supplier_account_type, type: :string, stored: true,
        as: ACCOUNT_TYPE_SQL.call("supplier_account_kind")
      t.string :moss_balance_account_number, null: true, comment: "CSV Moss Balance Account"
      t.string :moss_balance_account_kind, null: true
      t.virtual :moss_balance_account_type, type: :string, stored: true,
        as: ACCOUNT_TYPE_SQL.call("moss_balance_account_kind")
      t.string :cash_in_transit_account_number, null: true, comment: "CSV Cash in Transit Account"
      t.string :cash_in_transit_account_kind, null: true
      t.virtual :cash_in_transit_account_type, type: :string, stored: true,
        as: ACCOUNT_TYPE_SQL.call("cash_in_transit_account_kind")

      # ---- Card & employee
      t.string :cardholder, null: true
      t.string :card_used, null: true, comment: "e.g. VIRTUAL - 2557 (last 4 card digits)"
      t.string :card_holder_name, null: true
      t.string :card_holder_label, null: true, comment: "Constantly Kreditkarteninhaber"
      t.string :card_label, null: true, comment: "Constantly Kreditkarte"
      t.string :card_purpose, null: true
      t.string :team_name, null: true
      t.string :approver_name, null: true
      t.string :post_spend_approval_status, null: true, comment: "APPROVED or NA"

      # ---- Text / links / references
      t.string :reason_for_purchase, null: true
      t.string :parent_booking_text, null: true,
        comment: "Booking text of the whole transaction"
      t.string :invoice_number, null: true,
        comment: "= DATEV Belegfeld 1: bridge to datev_bookings.document_field_1 (step-1 booking EXPENSE -> creditor)"
      t.string :invoice_file_name, null: true,
        comment: "Receipt file names (several, pipe-separated)"
      t.string :sage_payment_type, null: true, comment: "PA or PR"
      t.string :sage_transaction_type, null: true, comment: "PI or PC"

      # --- other columns
      t.jsonb :other_moss_columns, default: {}, null: false, comment: "Transaction-level Moss columns without a dedicated column"

      # ---- WSJRDP specific
      # Polymorphic subject like moss_balance_movements / wsjrdp_camt_transactions /
      # accounting_entries carry it (usually a Person, e.g. the cardholder).
      t.bigint :subject_id, null: true
      t.string :subject_type, null: true
      t.string :source_file, null: true,
        comment: "File of the CSV import that inserted or last genuinely changed this row"
      t.text :comment, default: "", null: false
      t.string :status, null: true, comment: "Manual status (not from the import), preserved on import"
      t.jsonb :additional_info, default: {}, null: false

      t.index [:card_transaction_uuid], name: "index_moss_card_transactions_uuid", unique: true
      t.index [:invoice_number], name: "index_moss_card_transactions_invoice_number"
      t.index [:subject_type, :subject_id], name: "index_moss_card_transactions_subject"
      # Listing/filter performance: default sort plus the columns the card
      # transaction list filters on (the FIN views themselves follow later).
      t.index [:booking_date], name: "index_moss_card_transactions_booking_date"
      t.index [:payment_date], name: "index_moss_card_transactions_payment_date"
      t.index [:total_base_amount], name: "index_moss_card_transactions_total_base_amount"
      t.index [:transaction_state], name: "index_moss_card_transactions_transaction_state"
      t.index [:cardholder], name: "index_moss_card_transactions_cardholder"
      t.index [:clearing_datev_booking_id], name: "index_moss_card_transactions_clearing_datev", unique: true

      t.check_constraint "supplier_account_kind IS NULL OR supplier_account_kind IN #{ACCOUNT_KINDS_SQL}",
        name: "chk_moss_card_transaction_supplier_account_kind"
      t.check_constraint "moss_balance_account_kind IS NULL OR moss_balance_account_kind IN #{ACCOUNT_KINDS_SQL}",
        name: "chk_moss_card_transaction_moss_balance_account_kind"
      t.check_constraint "cash_in_transit_account_kind IS NULL OR cash_in_transit_account_kind IN #{ACCOUNT_KINDS_SQL}",
        name: "chk_moss_card_transaction_cash_in_transit_account_kind"
    end

    add_foreign_key :moss_card_transactions, :datev_bookings,
      column: :clearing_datev_booking_id, on_delete: :nullify
  end

  # One row per split of a Moss card transaction: the fields that differ per split.
  def create_moss_card_transaction_bookings
    create_table :moss_card_transaction_bookings, id: :bigserial, force: :cascade,
      comment: "Splits (bookings) of Moss card transactions" do |t|
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :updated_at, null: true

      # ---- Row keys
      t.string :unique_item_number, null: true,
        comment: "Unique per-line/booking key"
      t.integer :sub_row_number, default: 0, null: false,
        comment: "Split position within the transaction (WSJ27, 1-based)"

      t.uuid :card_transaction_uuid, null: false, comment: "mandatory n:1 moss_card_transactions"

      # The step-1 DATEV booking of this split (see header): strict 1:1, optional.
      t.bigint :expense_datev_booking_id, null: true,
        comment: "1:1 -> datev_bookings: step-1 booking Sachkonto -> creditor (receipt/expense)"
      t.jsonb :expense_datev_booking_link_meta, default: {}, null: false,
        comment: "Provenance of expense_datev_booking_id: created_at, author_id, score, automatic_manual"

      t.jsonb :other_moss_columns, default: {}, null: false,
        comment: "Booking-level WSJ27 CSV columns without a dedicated column"

      # ---- Amounts & currencies (per split/line; see header for the sign rules)
      # base = Moss Home (our ledger currency), transaction = Moss Original
      # (as transacted). Signed inputs, unsigned views generated. base_amount is
      # the reconciliation anchor against datev_bookings.base_amount.
      t.decimal :signed_base_amount, precision: 20, scale: 3, null: false,
        comment: "CSV Home Amount -- signed (+ = inflow, i.e. refund; card purchases are negative)"
      t.virtual :base_amount, type: :decimal, precision: 20, scale: 3, stored: true,
        as: "ABS(signed_base_amount)",
        comment: "Sign-less base-currency amount; reconciliation anchor against datev_bookings.base_amount"
      t.decimal :signed_transaction_amount, precision: 20, scale: 3, null: false,
        comment: "CSV Original Amount -- signed, in the currency the card was charged in"
      t.virtual :transaction_amount, type: :decimal, precision: 20, scale: 3, stored: true,
        as: "ABS(signed_transaction_amount)",
        comment: "Sign-less transaction-currency amount"
      t.virtual :debit_credit, type: :string, stored: true,
        as: "CASE WHEN signed_base_amount > 0 THEN 'C' ELSE 'D' END",
        comment: "Debit/credit of the expense side, derived from the sign: D = purchase, C = refund (matches the S/H of the step-1 DATEV booking)"
      t.string :base_currency, null: false,
        comment: "CSV Home Currency -- our ledger currency, always EUR (check-constrained)"
      t.string :transaction_currency, null: false, comment: "CSV Original Currency"
      t.decimal :exchange_rate, precision: 28, scale: 12, null: true,
        comment: "transaction = base * exchange_rate (EUR->PLN ~ 4.24)"

      # ---- Accounting (per split)
      t.string :account_number, null: true, comment: "Ledger (expense) account of this booking"
      t.string :account_kind, null: true,
        comment: "DATEV Kontenart of account_number, derived by the importer (UNKNOWN when the number is not classifiable); nullable for rows created outside the import"
      t.virtual :account_type, type: :string, stored: true,
        as: ACCOUNT_TYPE_SQL.call("account_kind"),
        comment: "Target class of the polymorphic `account` association"
      t.string :name_of_expense_account, null: true
      t.string :cost_center_number, null: true,
        comment: "Links to wsjrdp_cost_centers; = DATEV KOST1. CSV Cost Center - Name is ignored"
      t.string :sphere_number, null: true,
        comment: "CSV Cost Carrier - Number = tax sphere of this booking (mostly 3 = Zweckbetrieb); Cost Carrier - Name is ignored"
      t.string :distribution_combination, null: true
      t.string :posting_text, default: "", null: false, comment: "CSV Note -- booking text of this booking"

      # ---- WSJRDP specific
      # Like datev_bookings, every booking row records the file that inserted or
      # last genuinely changed it -- a re-import that changes nothing leaves it alone.
      t.string :source_file, null: true,
        comment: "File of the CSV import that inserted or last genuinely changed this row"
      t.text :comment, default: "", null: false,
        comment: "Manual note on this single booking (not from the import), preserved on import"
      t.jsonb :additional_info, default: {}, null: false,
        comment: "Reserved for our own, non-Moss extension data"

      t.index [:unique_item_number], name: "index_moss_card_transaction_bookings_unique_item_number", unique: true
      t.index [:card_transaction_uuid, :sub_row_number], name: "index_moss_card_transaction_bookings_uuid_sub_row", unique: true
      t.index [:expense_datev_booking_id], name: "index_moss_card_transaction_bookings_expense_datev", unique: true
      # Booking-level filters (Sachkonto / Kostenstelle / Betrag), reached
      # through a join from the transaction (the FIN views follow later).
      t.index [:account_number], name: "index_moss_card_transaction_bookings_account_number"
      t.index [:cost_center_number], name: "index_moss_card_transaction_bookings_cost_center_number"
      t.index [:base_amount], name: "index_moss_card_transaction_bookings_base_amount"

      t.check_constraint "base_currency = 'EUR'",
        name: "chk_moss_card_transaction_booking_base_currency"
      t.check_constraint "account_kind IS NULL OR account_kind IN #{ACCOUNT_KINDS_SQL}",
        name: "chk_moss_card_transaction_booking_account_kind"
    end

    add_foreign_key :moss_card_transaction_bookings, :datev_bookings,
      column: :expense_datev_booking_id, on_delete: :nullify
  end
end
