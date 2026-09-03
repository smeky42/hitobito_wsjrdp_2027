# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Unify the two Moss ledgers (card transactions and balance movements)
# into ONE three-level model. Design and the data analysis behind
# every decision: doc/plans/2026-08_moss-transaction-unification.md.
#
# THE THREE LEVELS
#   L1 moss_transactions -- one row per Moss transaction (a card payment is one;
#      an invoice, reimbursement or top-up has exactly one payment in Moss,
#      not modelled as a row of its own). Total amount,
#      currencies and exchange rate, the creditor, the wallet/transit accounts
#      and all outbound reconciliation links live here.
#   L2 moss_expenses     -- one row per expense of a reimbursement (N); a card
#      payment, invoice or top-up gets exactly one SHELL row that carries
#      nothing kind-specific: in Moss's own model those kinds have no middle
#      level, the transaction is the expense.
#   L3 moss_bookings     -- one row per split. This is the level DATEV books at
#      and the level we want to reconcile cent-exact; it carries just the split
#      dimensions (Sachkonto, Kostenstelle, Sphaere, Buchungstext, amount).
#
#   Every transaction has >= 1 expense and every expense >= 1 booking, so the
#   sum invariant holds at all three levels:
#     transactions.signed_total_base_amount
#       = SUM(expenses.signed_expense_base_amount)
#       = SUM(bookings.signed_base_amount)
#   It is asserted at the end of `up` (see check_sum_invariant!).
#
# STI: moss_transactions.type is MossCardTransaction | MossInvoice |
# MossReimbursement | MossTopUp, moss_expenses.type the matching ...Expense
# class; moss_bookings has no STI (a booking is the same for every kind).
#
# PREREQUISITE -- run accounting_tools/enrich_moss_balance_movements.py FIRST.
# The balance-movements export collapses a reimbursement expense's internal
# split into ONE row, so an expense Moss actually split across two
# bookings arrives as a single amount on one of them (proven against DATEV --
# the affected rows are listed below). Since a migration reads no CSV, that script
# writes the real booking list into moss_balance_movements.additional_info
# ('moss_bookings') beforehand. The guard below refuses to run without it --
# BEFORE the first schema change, so a missing enrichment costs nothing.
#
# The contribution link lives at the accounting-entry side
# (accounting_entries.moss_booking_id, 1 booking : N entries);
# accounting_entries.moss_balance_movement_id is
# dropped here and rebuilt by `down`.
class UnifyMossTransactions < ActiveRecord::Migration[7.1]
  # Same closed set as datev_bookings / moss_card_transactions (R5).
  ACCOUNT_KINDS_SQL = "('BANK', 'TRANSIT', 'CLEARING', 'LIABILITY', " \
    "'CREDITOR', 'DEBITOR', 'INCOME', 'EXPENSE', 'EQUITY', 'UNKNOWN')"

  ACCOUNT_TYPE_SQL = lambda do |kind_column|
    "CASE WHEN #{kind_column} IS NULL THEN NULL " \
      "WHEN #{kind_column} IN ('CREDITOR', 'DEBITOR') THEN 'WsjrdpPersonalAccount' " \
      "ELSE 'WsjrdpLedgerAccount' END"
  end

  # Kontenart from a (2026 chart) account number -- the SQL twin of
  # wsjrdp2027.datev.account_kind_for_account_number, inlined so the migration
  # needs no helper function of its own.
  ACCOUNT_KIND_SQL = lambda do |account_column|
    <<~SQL.squish
      CASE
        WHEN #{account_column} IS NULL OR #{account_column} = '' THEN NULL
        WHEN length(#{account_column}) = 6 AND left(#{account_column}, 1) = '7' THEN 'CREDITOR'
        WHEN #{account_column} = '36100' THEN 'CLEARING'
        WHEN #{account_column} = '13720' THEN 'TRANSIT'
        WHEN left(#{account_column}, 2) = '18' THEN 'BANK'
        WHEN left(#{account_column}, 1) = '4' THEN 'INCOME'
        WHEN left(#{account_column}, 1) = '6' THEN 'EXPENSE'
        WHEN left(#{account_column}, 1) = '3' THEN 'LIABILITY'
        WHEN left(#{account_column}, 1) = '9' THEN 'EQUITY'
        ELSE 'UNKNOWN'
      END
    SQL
  end

  # The legacy card tables kept these mostly-empty CSV columns under
  # snake_case keys on the HEADER; the unified tables keep every raw Moss field
  # under its CSV HEADER, on the level it belongs to. The payment's AND the
  # expense's facts (file, card acceptor, ticket, deferral) stay on L1 -- in
  # Moss the card transaction is the expense, so the L2 shell of a card payment
  # carries nothing -- while the line's facts (VAT, client code) go to every
  # split. `up` re-keys and lifts them (the supplier IBAN/BIC go to additional_info as
  # legacy_supplier_* for `down`), `down` puts them back, so the round trip
  # stays exact.
  CARD_LEGACY_TX_KEYS = {
    "record_type" => "Record Type",
    "supplier_vat_id" => "Supplier Vat ID",
    "card_acceptor_name" => "Card Acceptor Name",
    "airline_ticket_number" => "Airline Ticket Number",
    "number_of_months_in_release_plan" => "Number of Months in Release Plan",
    "prepayment_start_date" => "Prepayment Start Date",
    "prepayment_end_date" => "Prepayment End Date"
  }.freeze
  CARD_LEGACY_LINE_KEYS = {
    "vat_code" => "VAT Code",
    "vat_name" => "VAT Name",
    "vat_rate" => "VAT Rate",
    "client_number" => "Client Number"
  }.freeze
  # The legacy booking jsonb; its original_expense_account (always the account
  # number) is not carried, `down` derives it again.
  CARD_LEGACY_BOOKING_KEYS = {
    "unit_price" => "Unit Price",
    "quantity" => "Quantity"
  }.freeze

  def up
    guard_enrichment!

    create_moss_transactions
    create_moss_expenses
    create_moss_bookings

    backfill_card
    backfill_balance
    check_sum_invariant!

    move_contribution_link
    drop_legacy_tables
  end

  def down
    recreate_moss_card_transactions
    recreate_moss_card_transaction_bookings
    recreate_moss_balance_movements

    restore_card
    restore_balance
    restore_contribution_link

    drop_table :moss_bookings
    drop_table :moss_expenses
    drop_table :moss_transactions
  end

  private

  # --------------------------------------------------------------- guard (0)

  # Runs BEFORE any schema change: every reimbursement row must carry its
  # complete booking list and its expense uuid, and the known multi-booking rows
  # must list more than one booking. Raises (leaving the schema untouched)
  # otherwise -- see accounting_tools/enrich_moss_balance_movements.py.
  def guard_enrichment!
    incomplete = select_values(<<~SQL.squish)
      SELECT unique_item_number FROM moss_balance_movements
       WHERE coalesce(moss_reimbursement_id, '') <> ''
         AND (coalesce(jsonb_array_length(additional_info -> 'moss_bookings'), 0) = 0
              OR additional_info ->> 'moss_expense_uuid' IS NULL)
       ORDER BY unique_item_number
    SQL
    return if incomplete.empty?

    raise <<~MESSAGE
      Moss enrichment missing -- run accounting_tools/enrich_moss_balance_movements.py first.
        reimbursement rows without a complete additional_info->'moss_bookings': #{incomplete.size}
        known split rows not expanded: #{not_expanded.join(", ").presence || "none"}
    MESSAGE
  end

  # ---------------------------------------------------------------- schema (1)

  def create_moss_transactions
    create_table :moss_transactions, id: :bigserial, force: :cascade,
      comment: "L1: one row per Moss transaction (card payment, invoice, reimbursement, top-up)" do |t|
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :updated_at, null: true

      # ---- kind (STI) and Moss identity
      t.string :type, null: false,
        comment: "STI: MossCardTransaction | MossInvoice | MossReimbursement | MossTopUp"
      # Named after the Moss API's expenseType values (CARD_TRANSACTION,
      # INVOICE, REIMBURSEMENT); top_up is ours -- a top-up is not an expense
      # in Moss but a wallet movement.
      t.virtual :expense_type, type: :string, stored: true,
        as: "CASE type WHEN 'MossCardTransaction' THEN 'card_transaction' " \
            "WHEN 'MossInvoice' THEN 'invoice' " \
            "WHEN 'MossReimbursement' THEN 'reimbursement' ELSE 'top_up' END"
      t.uuid :moss_transaction_uuid, null: false, comment: "CSV Transaction ID (card + balance exports)"
      # ACCEPTED on every exported row so far (the exports contain booked
      # payments only). By the API spec this is the payment's
      # CardTransactionMetadata.transactionStatus (PENDING, ACCEPTED, REVERSED,
      # REJECTED) -- inferred from the spec, not observed. The website's status
      # display was left out of the label walkthrough.
      # The state of the payment, not the expense workflow status (that is invoice_status).
      t.string :moss_transaction_state, null: true, comment: "CSV Transaction State (card + balance exports)"
      t.string :status, null: true, comment: "App-side status"
      # STANDARD, or CREDIT on a card refund.
      t.string :transaction_type, null: true, comment: "CSV Transaction Type (card + balance exports)"

      # ---- dates. The per-kind DATEV date anchor (all L1 columns):
      #               card -- booking_date
      #               reimbursement -- submitted_on
      #               invoice -- invoice_date
      # Each anchor is matched against datev_bookings.booking_date (the DATEV
      # Belegdatum); an invoice's delivery_date is its second-best anchor.
      # Website labels (walkthrough of 2026-09-03, plan section 6a): Payment
      # Date = "Transaktionsdatum" on the card page and "Zahlungsdatum" on the
      # payment view of a balance kind; Booking Date = "Buchungsdatum" on the
      # card page (checked on payments whose Settlement Date differs) and
      # "Bezahlt am" on the invoice page, not shown for a reimbursement;
      # Service Date = "Leistungsdatum"; Approval Date = "Freigegeben am";
      # Settlement Date, Receipt Date and the export dates are not shown.
      t.date :payment_date, null: true, comment: "CSV Payment Date (card + balance exports)"
      t.date :booking_date, null: true, comment: "CSV Booking Date (card + balance exports)"
      t.date :first_export_date, null: true, comment: "CSV First Export Date (card + balance exports)"
      # Constant per invoice; the balance and reimbursement exports have no such column.
      t.date :last_export_date, null: true, comment: "CSV Last Export Date (card + invoice exports)"
      t.date :settlement_date, null: true, comment: "CSV Settlement Date (card export)"
      t.date :receipt_date, null: true, comment: "CSV Receipt Date (card export)"
      t.date :service_date, null: true, comment: "CSV Service Date (card export)"
      # Approval Date and Approver Name are constant per transaction in the
      # reimbursement and invoice exports.
      t.date :approval_date, null: true, comment: "CSV Approval Date (card, reimbursement and invoice exports)"
      # The invoice's own dates and its workflow status. By the API spec they
      # are header facts (expenseTime of an INVOICE header = the invoice date,
      # InvoiceMetadata.dueDate / deliveryDate, Expense.status) -- inferred
      # from the spec -- so they live here, not on the invoice's L2 shell.
      # Website (invoice page): "Rechnungsdatum", "Lieferdatum",
      # "Nettofaelligkeit" (Due Date and the Net Due Date key are equal on
      # every invoice so far, so the page cannot tell them apart); Submitted
      # Date is not shown. Invoice Status reads Completed on every exported
      # invoice; its display was left out of the walkthrough.
      t.date :invoice_date, null: true, comment: "CSV Invoice Date (invoice export)"
      # The invoice's workflow status; NULL for the other kinds.
      t.string :invoice_status, null: true, comment: "CSV Invoice Status (invoice export)"
      t.date :due_date, null: true, comment: "CSV Due Date (invoice export)"
      t.date :delivery_date, null: true, comment: "CSV Delivery Date (invoice export)"
      t.date :submitted_date, null: true, comment: "CSV Submitted Date (invoice export)"
      # The reimbursement's own dates. Website: Submitted On = "Beantragt am";
      # the creation date is not shown. By the API spec Submitted On is the
      # header's expenseTime and Creation date its createTime (inferred).
      t.date :created_in_moss_on, null: true, comment: "CSV Creation date (reimbursement export)"
      # The day the claim was submitted.
      t.date :submitted_on, null: true,
        comment: "CSV Submitted On (reimbursement export)"

      # ---- money. A transaction represents ONE payment, so currencies and the rate
      # belong here and nowhere else; the amounts exist at all three levels.
      # Signed (+ = inflow); equals the sum of its expenses and of its bookings
      # (the sum invariant).
      t.decimal :signed_total_base_amount, precision: 20, scale: 3, null: false,
        comment: "CSV Total Amount (card export) / sum of CSV Amount (balance export)"
      t.virtual :total_base_amount, type: :decimal, precision: 20, scale: 3, stored: true,
        as: "ABS(signed_total_base_amount)"
      # The same total in the transaction currency.
      t.decimal :signed_total_transaction_amount, precision: 20, scale: 3, null: true,
        comment: "CSV Total Original Amount (card export) / sum of CSV Original Amount (balance export)"
      t.virtual :total_transaction_amount, type: :decimal, precision: 20, scale: 3, stored: true,
        as: "ABS(signed_total_transaction_amount)"
      # The base currency (EUR).
      t.string :currency, null: true, comment: "CSV Home Currency (card export) / CSV Currency (balance export)"
      # The transaction currency.
      t.string :currency_original, null: true, comment: "CSV Original Currency (card + balance exports)"
      # The balance export reports 1.0 even on a foreign-currency payment, so the
      # rate comes from the detail exports; NULL unless the transaction currency
      # differs from the base currency.
      t.decimal :exchange_rate, precision: 28, scale: 12, null: true,
        comment: "CSV Conversion Rate (invoice + reimbursement exports)"
      # Website: the invoice page shows "Betrag" in the invoice's currency and
      # "Wechselkurs" = exchange_rate; the payment view shows "Gesamtbetrag"
      # = signed_total_base_amount (sign flipped), "Zahlungsgebuehren" =
      # payment_fee, "Fremdwaehrungsgebuehren" = fees_amount, "Zahlungsbetrag"
      # = the transaction-currency total, and a rate of its own that no export
      # carries: original amount / (total_amount_excluding_fees - payment_fee).
      # Conversion Rate Including Fees is 1.0 on every exported row so far.
      # The card export has no such column.
      t.decimal :payment_fee, precision: 20, scale: 3, null: true, comment: "CSV Payment Fee (balance export)"
      t.decimal :fees_amount, precision: 20, scale: 3, null: true, comment: "CSV Fees Amount (card + balance exports)"
      # Per transaction in the balance export, per split in the card export.
      t.decimal :total_amount_excluding_fees, precision: 20, scale: 3, null: true,
        comment: "CSV Transaction Amount Excluding Fees (balance export) / sum of CSV Transaction Amount Excluding Fees (card export)"
      t.decimal :conversion_rate_including_fees, precision: 28, scale: 12, null: true, comment: "CSV Conversion Rate Including Fees (card + balance exports)"

      # ---- creditor / counterparty (L1 for ALL kinds, reimbursements included)
      # 700002 (card), 700000 (balance) or an individual creditor 700xxx.
      t.string :supplier_account_number, null: true, comment: "CSV Supplier Account (card + balance exports)"
      t.string :supplier_account_kind, null: true, comment: "Kontenart, derived from the number"
      t.virtual :supplier_account_type, type: :string, stored: true,
        as: ACCOUNT_TYPE_SQL.call("supplier_account_kind")
      # The creditor's name, IBAN and BIC are NOT stored (decision of
      # 2026-09-03): they are standing data in wsjrdp_personal_accounts, reached
      # through supplier_account; the exports' copies would be a second
      # snapshot. The legacy tables carried them, so `up` keeps the legacy
      # values under additional_info (legacy_supplier_*) for `down` only.
      # Website: the payment view labels Recipient Account Number "Konto des
      # Empfaengers", Recipient Bank Code "BIC / Bankleitzahl" and the payee
      # "Name des Kontoinhabers" (the recipient name from the SEPA data of the
      # payee's Moss profile); the invoice page labels Supplier IBAN / BIC
      # "IBAN" / "BIC" and Supplier Account + Name together "Kreditor". The
      # top-up page shows the funding account with its full IBAN; only the
      # export truncates it. By the API spec a top-up is a BankTransaction of
      # type TOP_UP whose counterparty carries that account (inferred).
      # The account Moss paid to: the payee's on a reimbursement, the supplier's
      # on an invoice.
      t.string :recipient_iban, null: true, comment: "CSV Recipient Account Number (balance export)"
      t.string :recipient_bic, null: true, comment: "CSV Recipient Bank Code (balance export)"
      # The account holder paid, from the "<Name>; ; -" form of the field;
      # reimbursements and invoices only.
      t.string :recipient_name, null: true, comment: "Parsed from CSV Reason for Purchase (balance export)"
      # The funding account as '<organisation> - <IBAN>', cut off by Moss after 60
      # characters, kept verbatim.
      t.string :top_up_sender, null: true, comment: "CSV Reason for Purchase (balance export, top-ups)"

      # ---- Moss system accounts (the 3-step posting chain)
      # The wallet clearing account (36100).
      t.string :moss_balance_account_number, null: true, comment: "CSV Moss Balance Account (card + balance exports)"
      t.string :moss_balance_account_kind, null: true, comment: "Kontenart, derived from the number"
      t.virtual :moss_balance_account_type, type: :string, stored: true,
        as: ACCOUNT_TYPE_SQL.call("moss_balance_account_kind")
      # The Geldtransitkonto (13720).
      t.string :cash_in_transit_account_number, null: true, comment: "CSV Cash in Transit Account (card + balance exports)"
      t.string :cash_in_transit_account_kind, null: true, comment: "Kontenart, derived from the number"
      t.virtual :cash_in_transit_account_type, type: :string, stored: true,
        as: ACCOUNT_TYPE_SQL.call("cash_in_transit_account_kind")

      # ---- card-specific. By the API spec the merchant is a header fact
      # (CardTransactionMetadata.merchantDetails; inferred): the card header
      # is the expense, so nothing of this lives on the card payment's L2 shell.
      # Website (card page): Merchant Name = "Haendlername auf Abrechnung",
      # city and country not shown; Cardholder (card_holder_name) = "Karteninhaber"; "Karte" is
      # one linked field "<Card Purpose> *<last four digits of Card Used>" with
      # the digits muted; the other card fields, team, approver and post-spend
      # status are not shown. Approval Date / Approver Name = "Freigegeben am"
      # / "Freigegeben von" (reimbursement page).
      t.string :merchant_name, null: true, comment: "CSV Merchant Name (card export)"
      t.string :merchant_city, null: true, comment: "CSV Merchant City (card export)"
      t.string :merchant_country, null: true, comment: "CSV Merchant Country (card export)"
      # The card holder's full name and team; NULL for the other kinds.
      t.string :card_holder_name, null: true, comment: "CSV Cardholder (card export)"
      t.string :card_holder_team_name, null: true, comment: "CSV Team Name (card export)"
      # Card type and last four digits, e.g. 'VIRTUAL - 1234'.
      t.string :card_used, null: true, comment: "CSV Card Used (card export)"
      # The card's name in Moss (first name + unit).
      t.string :card_purpose, null: true, comment: "CSV Card Purpose (card export)"
      # The name as printed on the card (CSV Card Holder Name; the full name
      # or the same with abbreviated middle names)
      # and the two constant labels (CSV Card Holder Label / Card Label) are
      # keys of other_moss_columns.
      t.string :approver_name, null: true, comment: "CSV Approver Name (card, reimbursement and invoice exports)"
      t.string :post_spend_approval_status, null: true, comment: "CSV Post Spend Approval Status (card export)"
      # The balance export's Cardholder / Team Name on an invoice or a
      # reimbursement name the finance user who released the payout (two users
      # in the data, both card holders as well) and that user's team
      # ("Finance"); on a top-up both are empty.
      t.string :payout_user_name, null: true, comment: "CSV Cardholder (balance export, invoices and reimbursements)"
      t.string :payout_team_name, null: true, comment: "CSV Team Name (balance export, invoices and reimbursements)"

      # ---- texts and references. Website labels: "Buchungstext" for Parent
      # Booking Text (card, invoice) and for Reimbursement Description; "Name"
      # for Reimbursement Name (and for the expense's Expense Name on L2);
      # Payment Reference = "Verwendungszweck" on the payment view, unlabelled
      # on the reimbursement page; Invoice Number = "Belegnummer" (card page) /
      # "Rechnungsnummer" (invoice page); PO Number = "Bestellnummer"; PR
      # Number = "Kaufanfragen Nummer"; Submitted By = "Eingereicht von". By
      # the label rule the Buchungstext is the API's bookingText and the Name
      # its description (inferred). The Reimbursement Description is often empty.
      # The Buchungstext of the payment; empty where a reimbursement has no
      # description. Until the import ran, this migration seeds the balance kinds
      # with the house-normalised Payment Reference.
      t.string :transaction_posting_text, default: "", null: false,
        comment: "CSV Parent Booking Text (card + invoice exports) / CSV Reimbursement Description (reimbursement export)"
      # The Verwendungszweck of the outgoing payment; Moss appends our
      # organisation's name, which the normalisation removes. Not used for the
      # DATEV match.
      t.string :payment_reference, null: true,
        comment: "CSV Payment Reference (balance export), house-normalised"
      # The claim's title; NULL for the other kinds, whose exports carry no name.
      t.string :transaction_name, null: true,
        comment: "CSV Reimbursement Name (reimbursement export)"
      # DATEV Belegfeld 1: the bridge to datev_bookings.document_field_1.
      t.string :invoice_number, null: true,
        comment: "CSV Invoice Number (card + balance exports)"
      t.string :po_number, null: true, comment: "CSV PO Number (invoice export)"
      t.string :pr_number, null: true, comment: "CSV PR Number (invoice export)"
      # Who created the claim or uploaded the invoice; constant per transaction.
      t.string :submitted_by, null: true,
        comment: "CSV Submitted By (reimbursement + invoice exports)"
      t.uuid :moss_reimbursement_uuid, null: true, comment: "CSV Linked Reimbursement ID (balance export) = the reimbursement export's Unique Reimbursement ID"
      t.uuid :moss_invoice_uuid, null: true, comment: "CSV Linked Invoice ID (balance export) = the invoice export's Invoice ID"

      # ---- links (every outbound reconciliation link, each with provenance)
      # Set for every kind, card payments included.
      t.bigint :fin_account_id, null: true, comment: "The Moss wallet"
      t.bigint :recipient_id, null: true, comment: "Person the money is paid to (belongs_to :recipient)"
      t.jsonb :recipient_link_meta, default: {}, null: false, comment: "Provenance of recipient_id (doc/fin/recon_linking.md)"
      # Step 2 of the Moss posting chain; that DATEV booking carries the
      # transaction total.
      t.bigint :clearing_datev_booking_id, null: true,
        comment: "datev_bookings: the clearing booking (creditor -> 36100)"
      t.jsonb :clearing_datev_booking_link_meta, default: {}, null: false, comment: "Provenance of clearing_datev_booking_id (doc/fin/recon_linking.md)"
      # Top-ups only; matched on amount and date, since the export truncates the
      # funding IBAN.
      t.bigint :camt_transaction_id, null: true,
        comment: "wsjrdp_camt_transactions: the bank transfer that funded a top-up"
      t.jsonb :camt_transaction_link_meta, default: {}, null: false, comment: "Provenance of camt_transaction_id (doc/fin/recon_linking.md)"

      # ---- settled/booked outside the Moss export path
      # E.g. a creditor invoice paid straight from the bank, which reached DATEV
      # without the wallet.
      t.boolean :manually_paid, default: false, null: false,
        comment: "App-side flag: paid on a non-Moss route"
      # Moss marks such a payment exported although its DATEV bookings were
      # entered manually.
      t.boolean :manually_booked, default: false, null: false,
        comment: "App-side flag: DATEV bookings created by hand"

      # --- other_moss_columns keys, per export ---
      # other_moss_columns: every key is the CSV column header. Every header fact of Moss's Expense
      #   object lives here, for every kind (a card payment's or an invoice's expense IS its header).
      #   From the card export, when the cell has a value:
      #     'Card Holder Name', 'Card Holder Label', 'Card Label', 'Reason for Purchase',
      #     'General Transaction Type', 'Sage Payment Type', 'Sage Transaction Type',
      #     'Supplier Vat ID', 'Invoice File Name', 'Card Acceptor Name', 'Airline Ticket Number',
      #     'Is Prepayment?', 'Number of Months in Release Plan', 'Prepayment Start Date',
      #     'Prepayment End Date'
      #   and always, even when empty:
      #     'Total Amount', 'Total Amount (excl. VAT)', 'Total Original Amount',
      #     'Total Original Amount (excl. VAT)', 'VAT Amount', 'Original VAT', 'Fees Amount',
      #     'Currency', 'Home Currency', 'Original Currency', 'Conversion Rate',
      #     'Conversion Rate Including Fees'
      #   From the balance export (invoice, reimbursement, top-up), when the cell has a value:
      #     'Reason for Purchase', 'Moss Attachment URL'
      #   From the reimbursement / invoice export (header fields), when the cell has a value:
      #     'Supplier Vat ID', 'Reimbursement Payment Status', 'Reimbursement Name'
      #   From the invoice export (invoices), when the cell has a value:
      #     'Net Due Date', 'Invoice Payment Status', 'General Invoice Type', 'Is Prepayment?',
      #     'Prepayment Start Date', 'Prepayment End Date', 'Number of Months in Release Plan',
      #     'Payment term - Description', 'Payment term - Number', 'Discount 1 percentage',
      #     'Discount 1 due date', 'Discount 2 percentage', 'Discount 2 due date',
      #     'Invoice File Name', 'Reviewed by', 'Last reviewed', 'Verified By Name',
      #     'Verifier Names', 'Sage Transaction Type'
      #   and always, even when empty:
      #     'Currency', 'Home Currency', 'Original Currency', 'Conversion Rate',
      #     'Conversion Rate Including Fees', 'Fees Amount', 'Payment Fee',
      #     'Transaction Amount Excluding Fees'
      #   this migration (up), card rows: the legacy header's other_moss_columns minus the line keys lifted
      #     to L3, its snake_case keys re-keyed to their headers (CARD_LEGACY_TX_KEYS), plus
      #     'Reason for Purchase', 'General Transaction Type', 'Sage Payment Type',
      #     'Sage Transaction Type'
      #     and, when set, the legacy columns as
      #     'Invoice File Name', 'Is Prepayment?'
      #   this migration (up), balance rows:
      #     'Reason for Purchase', 'Moss Attachment URL', 'Conversion Rate'
      # additional_info: app-side annotations, plus the legacy creditor snapshot `down` needs
      #   (legacy_supplier_name and, on card rows, legacy_supplier_iban / legacy_supplier_bic),
      #   written by this migration (up).
      # --- end of the key list ---
      t.jsonb :other_moss_columns, default: {}, null: false,
        comment: "Raw Moss fields without a column, keyed by CSV header"
      t.string :source_file, null: true, comment: "The CSV file the row was last imported from"
      t.text :comment, default: "", null: false, comment: "App-side free text"
      t.jsonb :additional_info, default: {}, null: false,
        comment: "App-side annotations"

      t.index [:moss_transaction_uuid], name: "index_moss_transactions_uuid", unique: true
      t.index [:type], name: "index_moss_transactions_type"
      t.index [:payment_date], name: "index_moss_transactions_payment_date"
      t.index [:invoice_number], name: "index_moss_transactions_invoice_number"
      t.index [:total_base_amount], name: "index_moss_transactions_total_base_amount"
      t.index [:clearing_datev_booking_id], name: "index_moss_transactions_clearing_datev"
      t.index [:camt_transaction_id], name: "index_moss_transactions_camt"
      t.index [:recipient_id], name: "index_moss_transactions_recipient"

      t.check_constraint "type IN ('MossCardTransaction', 'MossInvoice', 'MossReimbursement', 'MossTopUp')",
        name: "chk_moss_transactions_type"
      t.check_constraint "supplier_account_kind IS NULL OR supplier_account_kind IN #{ACCOUNT_KINDS_SQL}",
        name: "chk_moss_transactions_supplier_account_kind"
      t.check_constraint "moss_balance_account_kind IS NULL OR moss_balance_account_kind IN #{ACCOUNT_KINDS_SQL}",
        name: "chk_moss_transactions_moss_balance_account_kind"
      t.check_constraint "cash_in_transit_account_kind IS NULL OR cash_in_transit_account_kind IN #{ACCOUNT_KINDS_SQL}",
        name: "chk_moss_transactions_cash_in_transit_account_kind"
    end

    add_foreign_key :moss_transactions, :datev_bookings,
      column: :clearing_datev_booking_id, on_delete: :nullify
    add_foreign_key :moss_transactions, :wsjrdp_camt_transactions,
      column: :camt_transaction_id, on_delete: :nullify
  end

  def create_moss_expenses
    create_table :moss_expenses, id: :bigserial, force: :cascade,
      comment: "L2: one row per expense of a reimbursement (N); one SHELL row for a card payment, invoice or top-up" do |t|
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :updated_at, null: true

      t.bigint :moss_transaction_id, null: false, comment: "FK moss_transactions (ON DELETE CASCADE)"
      t.uuid :moss_transaction_uuid, null: false, comment: "Denormalised; part of the natural key below"
      t.string :type, null: false,
        comment: "STI: MossCardTransactionExpense | MossInvoiceExpense | MossReimbursementExpense | MossTopUpExpense"
      # Only a reimbursement's expense has an id of its own; the other kinds carry
      # their transaction's.
      t.uuid :moss_expense_uuid, null: true,
        comment: "CSV Unique Expense ID (reimbursement export) / CSV Invoice ID (invoice export) / CSV Transaction ID (card + balance exports)"
      # The index of the expense within its transaction.
      t.integer :expense_number, default: 1, null: false,
        comment: "CSV Sub-row Number (balance export, reimbursements), else 1"

      # Signed; equals the sum of its bookings.
      t.decimal :signed_expense_base_amount, precision: 20, scale: 3, null: false,
        comment: "CSV Amount (balance export, reimbursements) / the transaction total (card, invoice, top-up)"
      t.virtual :expense_base_amount, type: :decimal, precision: 20, scale: 3, stored: true,
        as: "ABS(signed_expense_base_amount)"
      t.decimal :signed_expense_transaction_amount, precision: 20, scale: 3, null: true,
        comment: "CSV Original Amount (balance export, reimbursements) / the transaction total in the transaction currency"
      t.virtual :expense_transaction_amount, type: :decimal, precision: 20, scale: 3, stored: true,
        as: "ABS(signed_expense_transaction_amount)"

      # Everything below is a fact of a reimbursement's expense and NULL on the
      # shell rows of the other kinds, whose facts are transaction columns. By
      # the API spec an expense is a REIMBURSEMENT_INVOICE_LINE / MILEAGE_LINE
      # and Purchased On its expenseTime (inferred).
      # Website (expense): Expense Name = "Name", Parent Booking Text =
      # "Buchungstext", Purchased On = "Kaufdatum"; Expense type, Category and
      # Attached File Name are not shown; of the mileage keys KM Expense Type
      # = "Kilometersatz", Travel Route = "Reiseroute", Trip Distance In Unit
      # = "Gesamtdistanz". The Expense Name is mostly a merchant, a route on
      # mileage claims, otherwise free text.
      t.string :expense_posting_text, null: true,
        comment: "CSV Parent Booking Text (reimbursement export)"
      t.string :expense_name, null: true, comment: "CSV Expense Name (reimbursement export)"
      # EXPENSE or MILEAGE.
      t.string :moss_expense_type, null: true, comment: "CSV Expense type (reimbursement export)"
      t.date :purchased_on, null: true, comment: "CSV Purchased On (reimbursement export)"
      # --- other_moss_columns keys, per export ---
      # other_moss_columns: every key is the CSV column header. Only a reimbursement's expense carries
      #   keys; the shell rows of a card payment, invoice or top-up carry none (their facts are on L1).
      #   From the reimbursement export (expenses), when the cell has a value:
      #     'Attached File Name', 'KM Expense Type', 'Start Location', 'Destination Location',
      #     'Travel Route', 'Trip Type', 'Trip Distance In Unit', 'Reimbursable Distance In Unit',
      #     'Commute Deduction In Unit', 'Distance Unit', 'Vehicle Type'
      #   and, from the expense's own balance row, when the cell has a value:
      #     'Category'
      #   Card, invoice and top-up expenses (shell rows): nothing.
      #   this migration (up), reimbursement expenses (from the balance row, when set):
      #     'Category'
      #   this migration (up), card, invoice and top-up expenses: nothing.
      # additional_info: app-side annotations, plus what `down` needs to rebuild the flat
      #   reimbursement row -- written by this migration (up) on reimbursement expenses only:
      #     'legacy_balance_unique_item_number', 'legacy_balance_sub_row_number',
      #     'legacy_balance_account_number'
      # --- end of the key list ---
      t.jsonb :other_moss_columns, default: {}, null: false,
        comment: "Raw Moss fields without a column, keyed by CSV header"
      t.string :source_file, null: true, comment: "The CSV file the row was last imported from"
      t.text :comment, default: "", null: false, comment: "App-side free text"
      t.jsonb :additional_info, default: {}, null: false,
        comment: "App-side annotations"

      t.index [:moss_transaction_uuid, :expense_number],
        name: "index_moss_expenses_transaction_expense_number", unique: true
      t.index [:moss_transaction_id], name: "index_moss_expenses_transaction"
      t.index [:moss_expense_uuid], name: "index_moss_expenses_expense_uuid"
      t.index [:type], name: "index_moss_expenses_type"
    end

    add_foreign_key :moss_expenses, :moss_transactions, on_delete: :cascade
  end

  def create_moss_bookings
    create_table :moss_bookings, id: :bigserial, force: :cascade,
      comment: "L3: one row per split -- the grain DATEV books at" do |t|
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :updated_at, null: true

      # A direct link, so day-to-day SQL needs no expense join.
      t.bigint :moss_transaction_id, null: false, comment: "FK moss_transactions (ON DELETE CASCADE)"
      t.uuid :moss_transaction_uuid, null: false, comment: "Denormalised from the transaction"
      t.bigint :moss_expense_id, null: false, comment: "FK moss_expenses (ON DELETE CASCADE); never NULL"
      t.string :booking_unique_item_number, null: false,
        comment: "Constructed: <transaction uuid>_<CSV Sub-row Number> (card, invoice, top-up) / <CSV Unique Expense ID>_<CSV Sub-row Number> (reimbursement)"

      # Signed; the reconciliation anchor against datev_bookings.base_amount.
      t.decimal :signed_base_amount, precision: 20, scale: 3, null: false,
        comment: "CSV Home Amount (card export) / CSV Amount (balance + reimbursement exports)"
      t.virtual :base_amount, type: :decimal, precision: 20, scale: 3, stored: true,
        as: "ABS(signed_base_amount)"
      t.decimal :signed_transaction_amount, precision: 20, scale: 3, null: true,
        comment: "CSV Original Amount (card + balance exports) / CSV Amount in Original Currency (reimbursement export)"
      t.virtual :transaction_amount, type: :decimal, precision: 20, scale: 3, stored: true,
        as: "ABS(signed_transaction_amount)"
      # debit_credit: D = spend, C = refund or top-up; uniform within a transaction.
      t.virtual :debit_credit, type: :string, stored: true,
        as: "CASE WHEN signed_base_amount > 0 THEN 'C' ELSE 'D' END"

      # ---- the split dimensions (Moss splits along exactly these). Website
      # labels on every kind: "Sachkonto", "Kostenstelle", "Sphaere",
      # "Buchungstext"; the split amount is "Bruttobetrag" (card, reimbursement)
      # or "Betrag" (invoice line), shown with the sign flipped; the card and
      # invoice pages also show "Nettobetrag" and "Steuersatz" (jsonb keys).
      # The Sachkonto.
      t.string :account_number, null: true, comment: "CSV Account Number (card export) / CSV Expense Account (reimbursement export) / CSV Expense Account - Number (invoice export)"
      t.string :account_kind, null: true, comment: "Kontenart, derived from the number"
      t.virtual :account_type, type: :string, stored: true,
        as: ACCOUNT_TYPE_SQL.call("account_kind")
      # The Kostenstelle (DATEV KOST1); the reimbursement export mislabels the
      # number as a name; numbers may be alphanumeric.
      t.string :cost_center_number, null: true, comment: "CSV Cost Center - Number (card + invoice exports) / CSV Cost Center - Name (reimbursement export)"
      # The Sphaere (wsjrdp_spheres).
      t.string :sphere_number, null: true, comment: "CSV Cost Carrier - Number (card, reimbursement and invoice exports)"
      t.string :distribution_combination, null: true, comment: "CSV Distribution combination (card, reimbursement and invoice exports)"
      # The Buchungstext of this split.
      t.string :booking_posting_text, default: "", null: false,
        comment: "CSV Note (card export) / CSV Expense Description (reimbursement export) / CSV Booking Text (invoice export)"

      # ---- links
      # Step 1 of the Moss posting chain.
      t.bigint :expense_datev_booking_id, null: true,
        comment: "datev_bookings: the expense booking (Sachkonto -> creditor)"
      t.jsonb :expense_datev_booking_link_meta, default: {}, null: false, comment: "Provenance of expense_datev_booking_id (doc/fin/recon_linking.md)"
      t.bigint :contribution_subject_id, null: true,
        comment: "Person whose CONTRIBUTION (Beitrag) this booking concerns"
      t.string :contribution_subject_type, null: true, comment: "Polymorphic type of contribution_subject (Person)"

      # --- other_moss_columns keys, per export ---
      # other_moss_columns: every key is the CSV column header.
      #   Every kind, always: 'Unique Item Number' (the raw CSV value)
      #   From the card export (splits), when the cell has a value:
      #     'Unit Price', 'Quantity', 'VAT Code', 'VAT Name', 'VAT Rate', 'Client Number'
      #   and always, even when empty:
      #     'Amount', 'Amount (excl. VAT)', 'Home Amount', 'Original Amount',
      #     'Original Amount (excl. VAT)', 'Transaction Amount Excluding Fees'
      #   From the reimbursement export (splits), when the cell has a value:
      #     'VAT Code', 'VAT Name', 'VAT Rate'
      #   and, from the expense's balance row, when the cell has a value:
      #     'Client Number'
      #   and always, even when empty:
      #     'Amount', 'Amount (excl. VAT)', 'Amount in Original Currency', 'VAT Amount'
      #   From the invoice export (lines), when the cell has a value:
      #     'Unit Price', 'Quantity', 'VAT Code', 'VAT Name', 'VAT Rate'
      #   and, from the line's balance row, when the cell has a value:
      #     'Category', 'Client Number'
      #   and always, even when empty:
      #     'Amount', 'Amount in Home Currency', 'Net Amount', 'Net Amount in Home Currency',
      #     'Net Amount Negated', 'VAT Amount', 'VAT Amount in Home Currency'
      #   Top-ups (balance export), always: 'Unique Item Number', 'Amount (excl. VAT)';
      #     and, when the cell has a value:
      #     'Category', 'Client Number'
      #   this migration (up), card rows: the legacy booking's other_moss_columns with its snake_case
      #     keys re-keyed to their headers (CARD_LEGACY_BOOKING_KEYS; original_expense_account is not
      #     carried), plus 'Unique Item Number' and, lifted from the legacy header onto every split
      #     (CARD_LEGACY_LINE_KEYS), when set:
      #     'VAT Code', 'VAT Name', 'VAT Rate', 'Client Number'
      #   this migration (up), balance rows: 'Unique Item Number' always; 'Amount (excl. VAT)' and
      #     'Original Amount (excl. VAT)' on the first booking of each flat row (so `down` can sum an
      #     expanded reimbursement expense back); 'Client Number' on every booking of the row, when set;
      #     on invoice / top-up bookings, when set:
      #     'Category'
      #   The pre-migration enrichment's per-booking 'moss_unique_item_number' is read by this
      #     migration and stored here as 'Unique Item Number'.
      # additional_info: app-side annotations, plus what `down` needs to rebuild the flat
      #   invoice / top-up row. Written by
      #   this migration (up): the legacy row's additional_info minus the enrichment's scaffolding
      #     ('moss_bookings', 'moss_expense_uuid') -- today 'denylist_subject_candidates' on three
      #     bookings -- plus, on invoice / top-up bookings, 'legacy_balance_unique_item_number',
      #     'legacy_balance_sub_row_number';
      #   the pre-migration enrichment writes 'moss_bookings' (an array of
      #     objects with 'booking_unique_item_number', 'signed_base_amount', 'account_number',
      #     'cost_center_number', 'sphere_number', 'distribution_combination', 'booking_posting_text',
      #     'moss_unique_item_number') and 'moss_expense_uuid' into the LEGACY
      #     moss_balance_movements.additional_info.
      # --- end of the key list ---
      t.jsonb :other_moss_columns, default: {}, null: false,
        comment: "Raw Moss fields without a column, keyed by CSV header"
      t.string :source_file, null: true, comment: "The CSV file the row was last imported from"
      t.text :comment, default: "", null: false, comment: "App-side free text"
      t.jsonb :additional_info, default: {}, null: false,
        comment: "App-side annotations"

      t.index [:booking_unique_item_number], name: "index_moss_bookings_unique_item_number", unique: true
      t.index [:moss_transaction_id], name: "index_moss_bookings_transaction"
      t.index [:moss_expense_id], name: "index_moss_bookings_expense"
      t.index [:account_number], name: "index_moss_bookings_account_number"
      t.index [:base_amount], name: "index_moss_bookings_base_amount"
      t.index [:expense_datev_booking_id], name: "index_moss_bookings_expense_datev"
      t.index [:contribution_subject_type, :contribution_subject_id], name: "index_moss_bookings_contribution_subject"

      t.check_constraint "account_kind IS NULL OR account_kind IN #{ACCOUNT_KINDS_SQL}",
        name: "chk_moss_bookings_account_kind"
    end

    add_foreign_key :moss_bookings, :moss_transactions, on_delete: :cascade
    add_foreign_key :moss_bookings, :moss_expenses, on_delete: :cascade
    add_foreign_key :moss_bookings, :datev_bookings,
      column: :expense_datev_booking_id, on_delete: :nullify
  end

  # -------------------------------------------------------------- backfill (2)

  # SQL that moves the keys of `mapping` (old => new) within a jsonb value,
  # dropping the old keys and adding only those that have a value.
  def rekey_sql(column, mapping)
    drop = mapping.keys.map { |k| "- #{connection.quote(k)}" }.join(" ")
    "((#{column} #{drop}) || #{lift_sql(column, mapping)})"
  end

  # SQL for a NEW jsonb holding the keys of `mapping` (old => new) read from
  # `column`, only those that have a value -- to move keys to another level.
  def lift_sql(column, mapping)
    pairs = mapping.map { |old, new| "#{connection.quote(new)}, NULLIF(#{column} ->> #{connection.quote(old)}, '')" }
    "jsonb_strip_nulls(jsonb_build_object(#{pairs.join(", ")}))"
  end

  # SQL that drops the keys of the given mappings from a jsonb value.
  def minus_keys_sql(column, *mappings)
    drop = mappings.flat_map(&:keys).map { |k| "- #{connection.quote(k)}" }.join(" ")
    "(#{column} #{drop})"
  end

  # The wallet fin account the balance side already uses -- card transactions
  # join it here, so they finally appear in the Moss wallet too.
  def moss_wallet_fin_account_id
    @moss_wallet_fin_account_id ||= select_value(<<~SQL.squish)
      SELECT id FROM wsjrdp_fin_accounts WHERE transaction_type = 'MossBalanceMovement' ORDER BY id LIMIT 1
    SQL
  end

  def backfill_card
    execute <<~SQL
      INSERT INTO moss_transactions
        (type, moss_transaction_uuid, moss_transaction_state, status, transaction_type,
         payment_date, booking_date, first_export_date, last_export_date,
         settlement_date, receipt_date, service_date, approval_date,
         signed_total_base_amount, currency, currency_original,
         payment_fee, fees_amount, total_amount_excluding_fees, conversion_rate_including_fees,
         supplier_account_number, supplier_account_kind,
         moss_balance_account_number, moss_balance_account_kind,
         cash_in_transit_account_number, cash_in_transit_account_kind,
         merchant_name, merchant_city, merchant_country,
         card_holder_name, card_holder_team_name, card_used, card_purpose,
         approver_name, post_spend_approval_status,
         transaction_posting_text, invoice_number,
         clearing_datev_booking_id, clearing_datev_booking_link_meta,
         fin_account_id, other_moss_columns, additional_info, source_file, created_at, updated_at)
      SELECT
        'MossCardTransaction', h.card_transaction_uuid, h.transaction_state, h.status,
        h.transaction_type,
        h.payment_date, h.booking_date, h.first_export_date, h.last_export_date,
        h.settlement_date, h.receipt_date, h.service_date, h.approval_date,
        h.signed_total_base_amount, 'EUR', NULLIF(h.other_moss_columns ->> 'Original Currency', ''),
        (NULLIF(h.other_moss_columns ->> 'Payment Fee', ''))::numeric,
        (NULLIF(h.other_moss_columns ->> 'Fees Amount', ''))::numeric,
        (NULLIF(h.other_moss_columns ->> 'Transaction Amount Excluding Fees', ''))::numeric,
        (NULLIF(h.other_moss_columns ->> 'Conversion Rate Including Fees', ''))::numeric,
        h.supplier_account_number, h.supplier_account_kind,
        h.moss_balance_account_number, h.moss_balance_account_kind,
        h.cash_in_transit_account_number, h.cash_in_transit_account_kind,
        h.merchant_name, h.merchant_city, h.merchant_country,
        h.cardholder, h.team_name, h.card_used, h.card_purpose,
        h.approver_name, h.post_spend_approval_status,
        coalesce(h.parent_booking_text, ''), h.invoice_number,
        h.clearing_datev_booking_id, h.clearing_datev_booking_link_meta,
        #{moss_wallet_fin_account_id},
        -- the header's raw fields under their CSV headers: the legacy
        -- snake_case keys are re-keyed (IBAN/BIC go to additional_info for `down`; the
        -- line's keys move to L3), the legacy columns folded in, the receipt file's
        -- name and deferral flag only when set
        #{rekey_sql(minus_keys_sql("(h.other_moss_columns - 'supplier_iban' - 'supplier_bic')", CARD_LEGACY_LINE_KEYS), CARD_LEGACY_TX_KEYS)}
          || jsonb_build_object('Reason for Purchase', h.reason_for_purchase,
                                'General Transaction Type', h.general_transaction_type,
                                'Sage Payment Type', h.sage_payment_type,
                                'Sage Transaction Type', h.sage_transaction_type)
          || jsonb_strip_nulls(jsonb_build_object('Invoice File Name', NULLIF(h.invoice_file_name, ''),
                                                  'Is Prepayment?', NULLIF(h.is_prepayment, ''), 'Card Holder Name', NULLIF(h.card_holder_name, ''), 'Card Holder Label', NULLIF(h.card_holder_label, ''), 'Card Label', NULLIF(h.card_label, ''))),
        -- the legacy creditor snapshot, for `down` only
        jsonb_strip_nulls(jsonb_build_object('legacy_supplier_name', NULLIF(h.supplier_name, ''),
                                             'legacy_supplier_iban', NULLIF(h.other_moss_columns ->> 'supplier_iban', ''),
                                             'legacy_supplier_bic', NULLIF(h.other_moss_columns ->> 'supplier_bic', ''))),
        h.source_file, h.created_at, h.updated_at
      FROM moss_card_transactions h
    SQL

    # Exactly ONE shell expense per card transaction (the card payment IS the
    # expense; every fact of it is on the transaction).
    execute <<~SQL
      INSERT INTO moss_expenses
        (moss_transaction_id, moss_transaction_uuid, type, moss_expense_uuid, expense_number,
         signed_expense_base_amount, source_file, created_at, updated_at)
      SELECT mt.id, h.card_transaction_uuid, 'MossCardTransactionExpense', h.card_transaction_uuid, 1,
             h.signed_total_base_amount, h.source_file, h.created_at, h.updated_at
      FROM moss_card_transactions h
      JOIN moss_transactions mt ON mt.moss_transaction_uuid = h.card_transaction_uuid
    SQL

    # One booking per card split. The card header's comment and subject move
    # ONTO the booking(s) -- `up` never writes them to L1 or L2.
    execute <<~SQL
      INSERT INTO moss_bookings
        (moss_transaction_id, moss_transaction_uuid, moss_expense_id, booking_unique_item_number,
         signed_base_amount, signed_transaction_amount,
         account_number, account_kind, cost_center_number, sphere_number, distribution_combination,
         booking_posting_text, expense_datev_booking_id, expense_datev_booking_link_meta,
         contribution_subject_id, contribution_subject_type,
         other_moss_columns, source_file, comment, additional_info, created_at, updated_at)
      SELECT mt.id, h.card_transaction_uuid, e.id,
             h.card_transaction_uuid || '_' || b.sub_row_number,
             b.signed_base_amount, b.signed_transaction_amount,
             b.account_number, b.account_kind, b.cost_center_number, b.sphere_number,
             b.distribution_combination, b.posting_text,
             b.expense_datev_booking_id, b.expense_datev_booking_link_meta,
             h.subject_id, h.subject_type,
             -- the split's own keys re-keyed (the account name and the legacy
             -- original_expense_account, always the account number, are not
             -- carried); the header's per-line keys (VAT, client code) land on
             -- every split of the payment
             #{rekey_sql("(b.other_moss_columns - 'original_expense_account')", CARD_LEGACY_BOOKING_KEYS)}
               || jsonb_build_object('Unique Item Number', b.unique_item_number)
               || #{lift_sql("h.other_moss_columns", CARD_LEGACY_LINE_KEYS)},
             b.source_file,
             coalesce(NULLIF(concat_ws(' | ', NULLIF(b.comment, ''), NULLIF(h.comment, '')), ''), ''),
             b.additional_info, b.created_at, b.updated_at
      FROM moss_card_transaction_bookings b
      JOIN moss_card_transactions h ON h.card_transaction_uuid = b.card_transaction_uuid
      JOIN moss_transactions mt ON mt.moss_transaction_uuid = h.card_transaction_uuid
      JOIN moss_expenses e ON e.moss_transaction_id = mt.id
    SQL
  end

  def backfill_balance
    # L1: one header per Moss Transaction ID. The total is SUMMED -- the
    # balance-movements export has no transaction-total column.
    execute <<~SQL
      INSERT INTO moss_transactions
        (type, moss_transaction_uuid, moss_transaction_state, status, transaction_type,
         payment_date, booking_date, first_export_date,
         signed_total_base_amount, signed_total_transaction_amount, currency, currency_original, exchange_rate,
         payment_fee, fees_amount, total_amount_excluding_fees, conversion_rate_including_fees,
         supplier_account_number, supplier_account_kind,
         recipient_iban, recipient_bic,
         moss_balance_account_number, moss_balance_account_kind,
         cash_in_transit_account_number, cash_in_transit_account_kind,
         payout_team_name, payout_user_name,
         transaction_posting_text, payment_reference, invoice_number,
         moss_reimbursement_uuid, moss_invoice_uuid,
         fin_account_id, other_moss_columns, additional_info, source_file, created_at, updated_at)
      SELECT
        CASE WHEN coalesce(m.moss_reimbursement_id, '') <> '' THEN 'MossReimbursement'
             WHEN coalesce(m.moss_invoice_id, '') <> ''       THEN 'MossInvoice'
             ELSE 'MossTopUp' END,
        m.moss_transaction_id::uuid, m.transaction_state, m.status, m.transaction_type,
        m.payment_date, m.booking_date, m.first_export_date,
        g.total_signed, g.total_original, m.currency, m.original_currency,
        NULL,  -- exchange_rate: the balance export only carries the bogus 1.0; the real rate comes from the detail export at import
        m.payment_fee, m.fees_amount, m.transaction_amount_excluding_fees, m.conversion_rate_including_fees,
        m.supplier_account, #{ACCOUNT_KIND_SQL.call("m.supplier_account")},
        m.recipient_account_number, m.recipient_bank_code,
        m.moss_balance_account, #{ACCOUNT_KIND_SQL.call("m.moss_balance_account")},
        m.cash_in_transit_account, #{ACCOUNT_KIND_SQL.call("m.cash_in_transit_account")},
        m.team_name, m.cardholder,
        coalesce(m.payment_reference, ''), m.payment_reference, m.invoice_number,
        NULLIF(m.moss_reimbursement_id, '')::uuid, NULLIF(m.moss_invoice_id, '')::uuid,
        m.fin_account_id,
        -- every raw field that is constant per transaction, under its CSV
        -- header; the balance export's bogus 1.0 Conversion Rate is NOT used as
        -- exchange_rate (the real one arrives with the import) but kept, so
        -- `down` is exact. Category and Client Number are per ROW and go to
        -- the row's level below; the account names are not carried at all
        -- (`down` derives them from the standing data).
        jsonb_strip_nulls(jsonb_build_object('Reason for Purchase', m.reason_for_purchase,
                                             'Moss Attachment URL', NULLIF(m.moss_attachment_url, ''),
                                             'Conversion Rate', m.conversion_rate)),
        jsonb_strip_nulls(jsonb_build_object('legacy_supplier_name', NULLIF(m.supplier_name, ''))),  -- for `down` only
        NULL,  -- moss_balance_movements has no source_file column
        m.created_at, m.updated_at
      FROM (SELECT DISTINCT ON (moss_transaction_id) * FROM moss_balance_movements
             ORDER BY moss_transaction_id, sub_row_number) m
      JOIN (SELECT moss_transaction_id,
                   SUM(amount) AS total_signed,
                   SUM(original_amount) AS total_original
              FROM moss_balance_movements GROUP BY moss_transaction_id) g
        ON g.moss_transaction_id = m.moss_transaction_id
    SQL

    # L2 per kind: a reimbursement gets one expense PER balance row (each row is
    # one expense); an invoice gets exactly ONE expense for the whole
    # transaction (its several balance rows are the invoice's LINES, i.e.
    # bookings); a top-up gets one. A reimbursement expense keeps its row's
    # Category (one row = one expense); the legacy row identity goes to
    # additional_info so `down` can rebuild the flat rows exactly.
    execute <<~SQL
      INSERT INTO moss_expenses
        (moss_transaction_id, moss_transaction_uuid, type, moss_expense_uuid, expense_number,
         signed_expense_base_amount, signed_expense_transaction_amount,
         expense_posting_text, other_moss_columns, additional_info, source_file, created_at, updated_at)
      SELECT mt.id, mt.moss_transaction_uuid,
             CASE mt.type WHEN 'MossReimbursement' THEN 'MossReimbursementExpense'
                          WHEN 'MossInvoice'       THEN 'MossInvoiceExpense'
                          ELSE 'MossTopUpExpense' END,
             (m.additional_info ->> 'moss_expense_uuid')::uuid,
             CASE WHEN mt.type = 'MossReimbursement' THEN m.sub_row_number ELSE 1 END,
             CASE WHEN mt.type = 'MossReimbursement' THEN m.amount ELSE t.total_signed END,
             CASE WHEN mt.type = 'MossReimbursement' THEN m.original_amount ELSE t.total_original END,
             CASE WHEN mt.type = 'MossReimbursement' THEN NULLIF(m.note, '') END,
             CASE WHEN mt.type = 'MossReimbursement'
                  THEN jsonb_strip_nulls(jsonb_build_object('Category', m.category))
                  ELSE '{}'::jsonb END,
             -- what `down` needs to rebuild the flat reimbursement row: scaffolding, so additional_info
             CASE WHEN mt.type = 'MossReimbursement'
                  THEN jsonb_build_object('legacy_balance_unique_item_number', m.unique_item_number,
                                          'legacy_balance_sub_row_number', m.sub_row_number,
                                          'legacy_balance_account_number', m.account_number)
                  ELSE '{}'::jsonb END,
             NULL, m.created_at, m.updated_at
      FROM moss_balance_movements m
      JOIN moss_transactions mt ON mt.moss_transaction_uuid = m.moss_transaction_id::uuid
      JOIN (SELECT moss_transaction_id,
                   SUM(amount) AS total_signed,
                   SUM(original_amount) AS total_original
              FROM moss_balance_movements GROUP BY moss_transaction_id) t
        ON t.moss_transaction_id = m.moss_transaction_id
      WHERE mt.type = 'MossReimbursement'
         OR m.sub_row_number = (SELECT min(x.sub_row_number) FROM moss_balance_movements x
                                 WHERE x.moss_transaction_id = m.moss_transaction_id)
    SQL

    # L3: reimbursements expand their enriched booking list (the guard made sure
    # it is there); invoice and top-up rows become one booking each, derived 1:1
    # from the flat row, keeping the row's Category (one row = one booking); the
    # row's Client Number goes onto every booking of the row. No provisional
    # bookings anywhere. The flat row's excl.-VAT figures go onto the FIRST
    # booking of an expanded expense only, so `down` can sum the bookings back
    # to the row.
    execute <<~SQL
      INSERT INTO moss_bookings
        (moss_transaction_id, moss_transaction_uuid, moss_expense_id, booking_unique_item_number,
         signed_base_amount, signed_transaction_amount,
         account_number, account_kind, cost_center_number, sphere_number, distribution_combination,
         booking_posting_text, contribution_subject_id, contribution_subject_type,
         other_moss_columns, source_file, comment, additional_info, created_at, updated_at)
      SELECT mt.id, mt.moss_transaction_uuid, e.id,
             coalesce(s.booking ->> 'booking_unique_item_number',
                      mt.moss_transaction_uuid || '_' || m.sub_row_number),
             coalesce((s.booking ->> 'signed_base_amount')::numeric, m.amount),
             CASE WHEN s.booking IS NULL THEN m.original_amount END,
             coalesce(s.booking ->> 'account_number', m.account_number),
             #{ACCOUNT_KIND_SQL.call("coalesce(s.booking ->> 'account_number', m.account_number)")},
             s.booking ->> 'cost_center_number',
             s.booking ->> 'sphere_number',
             s.booking ->> 'distribution_combination',
             coalesce(s.booking ->> 'booking_posting_text', m.note, ''),
             m.subject_id, m.subject_type,
             jsonb_build_object('Amount (excl. VAT)',
                                CASE WHEN coalesce(s.ordinal, 1) = 1 THEN m.amount_excl_vat END,
                                'Original Amount (excl. VAT)',
                                CASE WHEN coalesce(s.ordinal, 1) = 1 THEN m.original_amount_excl_vat END,
                                'Unique Item Number',
                                coalesce(s.booking ->> 'moss_unique_item_number', m.unique_item_number))
               || jsonb_strip_nulls(jsonb_build_object('Client Number', NULLIF(m.client_number, '')))
               || CASE WHEN mt.type <> 'MossReimbursement'
                       THEN jsonb_strip_nulls(jsonb_build_object('Category', m.category))
                       ELSE '{}'::jsonb END,
             NULL, m.comment,
             -- the app's annotations minus the enrichment's scaffolding, plus what `down`
             -- needs to rebuild the flat invoice / top-up row
             (m.additional_info - 'moss_bookings' - 'moss_expense_uuid')
               || CASE WHEN mt.type <> 'MossReimbursement'
                       THEN jsonb_build_object('legacy_balance_unique_item_number', m.unique_item_number,
                                               'legacy_balance_sub_row_number', m.sub_row_number)
                       ELSE '{}'::jsonb END,
             m.created_at, m.updated_at
      FROM moss_balance_movements m
      JOIN moss_transactions mt ON mt.moss_transaction_uuid = m.moss_transaction_id::uuid
      JOIN moss_expenses e ON e.moss_transaction_id = mt.id
                          AND (mt.type <> 'MossReimbursement' OR e.expense_number = m.sub_row_number)
      LEFT JOIN LATERAL (
        SELECT value AS booking, ordinality AS ordinal
          FROM jsonb_array_elements(m.additional_info -> 'moss_bookings') WITH ORDINALITY
         WHERE mt.type = 'MossReimbursement'
      ) s ON true
    SQL
  end

  # The invariant is asserted INSIDE the migration: with the enrichment in place
  # there are no provisional rows and no exceptions, so it must hold exactly.
  def check_sum_invariant!
    broken = select_values(<<~SQL.squish)
      SELECT t.moss_transaction_uuid::text FROM moss_transactions t
       WHERE t.signed_total_base_amount
             <> (SELECT coalesce(SUM(e.signed_expense_base_amount), 0)
                   FROM moss_expenses e WHERE e.moss_transaction_id = t.id)
          OR t.signed_total_base_amount
             <> (SELECT coalesce(SUM(b.signed_base_amount), 0)
                   FROM moss_bookings b WHERE b.moss_transaction_id = t.id)
       ORDER BY 1
    SQL
    return if broken.empty?

    raise "Moss sum invariant violated for #{broken.size} transaction(s): #{broken.first(10).join(", ")}"
  end

  # ------------------------------------------------- contribution link (3)

  def move_contribution_link
    add_reference :accounting_entries, :moss_booking, null: true, index: true,
      foreign_key: {to_table: :moss_bookings, on_delete: :nullify}
    add_column :accounting_entries, :moss_booking_link_meta, :jsonb, default: {}, null: false
    add_column :accounting_entries, :camt_transaction_link_meta, :jsonb, default: {}, null: false

    # Deterministic: the legacy link points at one balance row = one expense
    # (reimbursement) or one booking (invoice/top-up); every legacy link sits
    # on a single-booking expense, and the migration aborts otherwise.
    execute <<~SQL
      UPDATE accounting_entries ae
         SET moss_booking_id = b.id
        FROM moss_balance_movements old
        JOIN moss_transactions mt ON mt.moss_transaction_uuid = old.moss_transaction_id::uuid
        JOIN moss_expenses e ON e.moss_transaction_id = mt.id
                            AND (mt.type <> 'MossReimbursement' OR e.expense_number = old.sub_row_number)
        JOIN moss_bookings b ON b.moss_expense_id = e.id
                            AND (b.additional_info ->> 'legacy_balance_unique_item_number' = old.unique_item_number
                                 OR mt.type = 'MossReimbursement')
       WHERE ae.moss_balance_movement_id = old.id
    SQL

    unmapped = select_value(<<~SQL.squish)
      SELECT count(*) FROM accounting_entries
       WHERE moss_balance_movement_id IS NOT NULL AND moss_booking_id IS NULL
    SQL
    raise "#{unmapped} accounting_entries could not be remapped to a Moss booking" if unmapped.to_i.positive?

    remove_column :accounting_entries, :moss_balance_movement_id
  end

  def drop_legacy_tables
    drop_table :moss_card_transaction_bookings
    drop_table :moss_card_transactions
    drop_table :moss_balance_movements
  end

  # ------------------------------------------------------------------ down

  def recreate_moss_card_transactions
    create_table :moss_card_transactions, id: :bigserial, force: :cascade,
      comment: "Moss card transactions: one row per Moss Transaction ID" do |t|
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :updated_at, null: true
      t.uuid :card_transaction_uuid, null: false
      t.string :transaction_state, null: true
      t.string :transaction_type, null: true
      t.string :general_transaction_type, null: true
      t.string :is_prepayment, null: true
      t.bigint :clearing_datev_booking_id, null: true
      t.jsonb :clearing_datev_booking_link_meta, default: {}, null: false
      t.date :payment_date, null: true
      t.date :booking_date, null: true
      t.date :settlement_date, null: true
      t.date :first_export_date, null: true
      t.date :last_export_date, null: true
      t.date :receipt_date, null: true
      t.date :service_date, null: true
      t.date :approval_date, null: true
      t.decimal :signed_total_base_amount, precision: 20, scale: 3, null: false
      t.virtual :total_base_amount, type: :decimal, precision: 20, scale: 3, stored: true,
        as: "ABS(signed_total_base_amount)"
      t.string :merchant_name, null: true
      t.string :merchant_city, null: true
      t.string :merchant_country, null: true
      t.string :supplier_name, null: true
      t.string :supplier_account_number, null: true
      t.string :supplier_account_kind, null: true
      t.virtual :supplier_account_type, type: :string, stored: true,
        as: ACCOUNT_TYPE_SQL.call("supplier_account_kind")
      t.string :moss_balance_account_number, null: true
      t.string :moss_balance_account_kind, null: true
      t.virtual :moss_balance_account_type, type: :string, stored: true,
        as: ACCOUNT_TYPE_SQL.call("moss_balance_account_kind")
      t.string :cash_in_transit_account_number, null: true
      t.string :cash_in_transit_account_kind, null: true
      t.virtual :cash_in_transit_account_type, type: :string, stored: true,
        as: ACCOUNT_TYPE_SQL.call("cash_in_transit_account_kind")
      t.string :cardholder, null: true
      t.string :card_used, null: true
      t.string :card_holder_name, null: true
      t.string :card_holder_label, null: true
      t.string :card_label, null: true
      t.string :card_purpose, null: true
      t.string :team_name, null: true
      t.string :approver_name, null: true
      t.string :post_spend_approval_status, null: true
      t.string :reason_for_purchase, null: true
      t.string :parent_booking_text, null: true
      t.string :invoice_number, null: true
      t.string :invoice_file_name, null: true
      t.string :sage_payment_type, null: true
      t.string :sage_transaction_type, null: true
      t.jsonb :other_moss_columns, default: {}, null: false
      t.bigint :subject_id, null: true
      t.string :subject_type, null: true
      t.string :source_file, null: true
      t.text :comment, default: "", null: false
      t.string :status, null: true
      t.jsonb :additional_info, default: {}, null: false

      t.index [:card_transaction_uuid], name: "index_moss_card_transactions_uuid", unique: true
      t.index [:invoice_number], name: "index_moss_card_transactions_invoice_number"
      t.index [:subject_type, :subject_id], name: "index_moss_card_transactions_subject"
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

  def recreate_moss_card_transaction_bookings
    create_table :moss_card_transaction_bookings, id: :bigserial, force: :cascade,
      comment: "Splits (bookings) of Moss card transactions" do |t|
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :updated_at, null: true
      t.string :unique_item_number, null: true
      t.integer :sub_row_number, default: 0, null: false
      t.uuid :card_transaction_uuid, null: false
      t.bigint :expense_datev_booking_id, null: true
      t.jsonb :expense_datev_booking_link_meta, default: {}, null: false
      t.jsonb :other_moss_columns, default: {}, null: false
      t.decimal :signed_base_amount, precision: 20, scale: 3, null: false
      t.virtual :base_amount, type: :decimal, precision: 20, scale: 3, stored: true,
        as: "ABS(signed_base_amount)"
      t.decimal :signed_transaction_amount, precision: 20, scale: 3, null: false
      t.virtual :transaction_amount, type: :decimal, precision: 20, scale: 3, stored: true,
        as: "ABS(signed_transaction_amount)"
      t.virtual :debit_credit, type: :string, stored: true,
        as: "CASE WHEN signed_base_amount > 0 THEN 'C' ELSE 'D' END"
      t.string :base_currency, null: false
      t.string :transaction_currency, null: false
      t.decimal :exchange_rate, precision: 28, scale: 12, null: true
      t.string :account_number, null: true
      t.string :account_kind, null: true
      t.virtual :account_type, type: :string, stored: true,
        as: ACCOUNT_TYPE_SQL.call("account_kind")
      t.string :name_of_expense_account, null: true
      t.string :cost_center_number, null: true
      t.string :sphere_number, null: true
      t.string :distribution_combination, null: true
      t.string :posting_text, default: "", null: false
      t.string :source_file, null: true
      t.text :comment, default: "", null: false
      t.jsonb :additional_info, default: {}, null: false

      t.index [:card_transaction_uuid, :sub_row_number],
        name: "index_moss_card_transaction_bookings_tx_sub_row", unique: true
      t.index [:unique_item_number], name: "index_moss_card_transaction_bookings_unique_item", unique: true
      t.index [:expense_datev_booking_id], name: "index_moss_card_transaction_bookings_expense_datev", unique: true
      t.index [:account_number], name: "index_moss_card_transaction_bookings_account_number"
      t.index [:base_amount], name: "index_moss_card_transaction_bookings_base_amount"

      t.check_constraint "account_kind IS NULL OR account_kind IN #{ACCOUNT_KINDS_SQL}",
        name: "chk_moss_card_transaction_bookings_account_kind"
      t.check_constraint "base_currency = 'EUR'", name: "chk_moss_card_transaction_bookings_base_currency"
    end

    add_foreign_key :moss_card_transaction_bookings, :datev_bookings,
      column: :expense_datev_booking_id, on_delete: :nullify
  end

  def recreate_moss_balance_movements
    create_table :moss_balance_movements, id: :serial, force: :cascade do |t|
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :updated_at, null: true
      t.bigint :fin_account_id, null: false
      t.bigint :subject_id, null: true
      t.string :subject_type, null: true
      t.text :comment, default: "", null: false
      t.string :status, null: true
      t.jsonb :additional_info, default: {}
      t.string :unique_item_number, null: false
      t.string :moss_transaction_id, null: false
      t.integer :sub_row_number, null: false, default: 0
      t.string :transaction_state, null: true
      t.string :transaction_type, null: true
      t.date :payment_date, null: false
      t.date :booking_date, null: false
      t.decimal :amount_excl_vat, precision: 20, scale: 3, null: true
      t.decimal :amount, precision: 20, scale: 3, null: false
      t.string :currency, null: false
      t.decimal :original_amount_excl_vat, precision: 20, scale: 3, null: true
      t.decimal :original_amount, precision: 20, scale: 3, null: true
      t.string :original_currency, null: true
      t.decimal :conversion_rate, precision: 20, scale: 8, null: true
      t.decimal :conversion_rate_including_fees, precision: 20, scale: 8, null: true
      t.decimal :fees_amount, precision: 20, scale: 3, null: true
      t.decimal :payment_fee, precision: 20, scale: 3, null: true
      t.decimal :transaction_amount_excluding_fees, precision: 20, scale: 3, null: true
      t.string :supplier_account, null: true
      t.string :supplier_name, null: true
      t.string :account_number, null: true
      t.string :name_of_expense_account, null: true
      t.string :category, null: true
      t.string :moss_balance_account, null: true
      t.string :cash_in_transit_account, null: true
      t.string :reason_for_purchase, null: true
      t.string :note, null: false, default: ""
      t.string :recipient_account_number, null: true
      t.string :recipient_bank_code, null: true
      t.string :payment_reference, null: true
      t.string :invoice_number, null: true
      t.string :team_name, null: true
      t.string :cardholder, null: true
      t.string :client_number, null: true
      t.date :first_export_date, null: true
      t.string :moss_expense_id, null: true
      t.string :moss_invoice_id, null: true
      t.string :moss_reimbursement_id, null: true
      t.string :moss_attachment_url, null: true

      t.index [:unique_item_number], name: "index_moss_balance_movements_unique_item_number", unique: true
      t.index [:moss_transaction_id, :sub_row_number], name: "index_moss_balance_movements_tx_id_sub_row", unique: true
      t.index [:subject_type, :subject_id], name: "index_moss_balance_movements_subject"
    end
  end

  def restore_card
    execute <<~SQL
      INSERT INTO moss_card_transactions
        (card_transaction_uuid, transaction_state, transaction_type, general_transaction_type, is_prepayment,
         clearing_datev_booking_id, clearing_datev_booking_link_meta,
         payment_date, booking_date, settlement_date, first_export_date, last_export_date,
         receipt_date, service_date, approval_date, signed_total_base_amount,
         merchant_name, merchant_city, merchant_country, supplier_name,
         supplier_account_number, supplier_account_kind,
         moss_balance_account_number, moss_balance_account_kind,
         cash_in_transit_account_number, cash_in_transit_account_kind,
         cardholder, card_used, card_holder_name, card_holder_label, card_label, card_purpose,
         team_name, approver_name, post_spend_approval_status,
         reason_for_purchase, parent_booking_text, invoice_number, invoice_file_name,
         sage_payment_type, sage_transaction_type, other_moss_columns,
         subject_id, subject_type, source_file, comment, status, additional_info,
         created_at, updated_at)
      SELECT t.moss_transaction_uuid, t.moss_transaction_state, t.transaction_type,
             t.other_moss_columns ->> 'General Transaction Type', t.other_moss_columns ->> 'Is Prepayment?',
             t.clearing_datev_booking_id, t.clearing_datev_booking_link_meta,
             t.payment_date, t.booking_date, t.settlement_date, t.first_export_date, t.last_export_date,
             t.receipt_date, t.service_date, t.approval_date, t.signed_total_base_amount,
             t.merchant_name, t.merchant_city, t.merchant_country, t.additional_info ->> 'legacy_supplier_name',
             t.supplier_account_number, t.supplier_account_kind,
             t.moss_balance_account_number, t.moss_balance_account_kind,
             t.cash_in_transit_account_number, t.cash_in_transit_account_kind,
             t.card_holder_name, t.card_used, t.other_moss_columns ->> 'Card Holder Name', t.other_moss_columns ->> 'Card Holder Label', t.other_moss_columns ->> 'Card Label', t.card_purpose,
             t.card_holder_team_name, t.approver_name, t.post_spend_approval_status,
             t.other_moss_columns ->> 'Reason for Purchase', NULLIF(t.transaction_posting_text, ''),
             t.invoice_number, t.other_moss_columns ->> 'Invoice File Name',
             t.other_moss_columns ->> 'Sage Payment Type', t.other_moss_columns ->> 'Sage Transaction Type',
             -- the header's legacy keys come back from L1 and, for the line keys, from the first split
             #{rekey_sql("(t.other_moss_columns - 'Reason for Purchase' - 'General Transaction Type' - 'Sage Payment Type' - 'Sage Transaction Type' - 'Invoice File Name' - 'Is Prepayment?' - 'Card Holder Name' - 'Card Holder Label' - 'Card Label')", CARD_LEGACY_TX_KEYS.invert)}
               || #{lift_sql("b.other_moss_columns", CARD_LEGACY_LINE_KEYS.invert)}
               || jsonb_strip_nulls(jsonb_build_object('supplier_iban', t.additional_info ->> 'legacy_supplier_iban', 'supplier_bic', t.additional_info ->> 'legacy_supplier_bic')),
             b.contribution_subject_id, b.contribution_subject_type,
             t.source_file, '', t.status,
             t.additional_info - 'legacy_supplier_name' - 'legacy_supplier_iban' - 'legacy_supplier_bic',
             t.created_at, t.updated_at
      FROM moss_transactions t
      JOIN moss_expenses e ON e.moss_transaction_id = t.id
      JOIN LATERAL (SELECT contribution_subject_id, contribution_subject_type, other_moss_columns
                      FROM moss_bookings WHERE moss_expense_id = e.id
                     ORDER BY booking_unique_item_number LIMIT 1) b ON true
      WHERE t.type = 'MossCardTransaction'
    SQL

    execute <<~SQL
      INSERT INTO moss_card_transaction_bookings
        (unique_item_number, sub_row_number, card_transaction_uuid,
         expense_datev_booking_id, expense_datev_booking_link_meta, other_moss_columns,
         signed_base_amount, signed_transaction_amount, base_currency, transaction_currency, exchange_rate,
         account_number, account_kind, name_of_expense_account,
         cost_center_number, sphere_number, distribution_combination, posting_text,
         source_file, comment, additional_info, created_at, updated_at)
      SELECT b.other_moss_columns ->> 'Unique Item Number',
             split_part(b.booking_unique_item_number, '_', 2)::integer,
             t.moss_transaction_uuid,
             b.expense_datev_booking_id, b.expense_datev_booking_link_meta,
             -- the split's keys back under their snake_case names; the header's
             -- per-line keys are dropped here (they return on the header) and the
             -- legacy original_expense_account is the account number again
             #{rekey_sql(minus_keys_sql("(b.other_moss_columns - 'Unique Item Number')", CARD_LEGACY_LINE_KEYS.invert), CARD_LEGACY_BOOKING_KEYS.invert)}
               || jsonb_strip_nulls(jsonb_build_object('original_expense_account', b.account_number)),
             b.signed_base_amount, coalesce(b.signed_transaction_amount, b.signed_base_amount),
             coalesce(t.currency, 'EUR'), coalesce(t.currency_original, 'EUR'),
             -- the legacy tables stored the export's Conversion Rate (1.0 on EUR rows);
             -- the unified column is NULL unless foreign, so fall back to the mirror
             coalesce(t.exchange_rate, NULLIF(t.other_moss_columns ->> 'Conversion Rate', '')::numeric),
             b.account_number, b.account_kind, la.name,
             b.cost_center_number, b.sphere_number, b.distribution_combination, b.booking_posting_text,
             b.source_file, '', b.additional_info, b.created_at, b.updated_at
      FROM moss_bookings b
      JOIN moss_transactions t ON t.id = b.moss_transaction_id
      LEFT JOIN wsjrdp_ledger_accounts la ON la.number = b.account_number
      WHERE t.type = 'MossCardTransaction'
    SQL
  end

  # One flat row per legacy balance row: for reimbursements that is the EXPENSE
  # (its bookings are summed back), for invoice/top-up the BOOKING. Both carry
  # their legacy identity in additional_info and the row's Category in
  # other_moss_columns (all written by `up`); the row's Client Number sits on
  # its booking(s), and the account name comes from the standing data.
  def restore_balance
    execute <<~SQL
      INSERT INTO moss_balance_movements
        (fin_account_id, subject_id, subject_type, comment, status, additional_info,
         unique_item_number, moss_transaction_id, sub_row_number,
         transaction_state, transaction_type, payment_date, booking_date,
         amount_excl_vat, amount, currency, original_amount_excl_vat, original_amount, original_currency,
         conversion_rate, conversion_rate_including_fees, fees_amount, payment_fee,
         transaction_amount_excluding_fees,
         supplier_account, supplier_name, account_number, name_of_expense_account, category,
         moss_balance_account, cash_in_transit_account, reason_for_purchase, note,
         recipient_account_number, recipient_bank_code, payment_reference, invoice_number,
         team_name, cardholder, client_number, first_export_date,
         moss_expense_id, moss_invoice_id, moss_reimbursement_id, moss_attachment_url,
         created_at, updated_at)
      -- reimbursements: one row per expense
      SELECT t.fin_account_id, b.contribution_subject_id, b.contribution_subject_type,
             b.comment, t.status, b.additional_info,
             e.additional_info ->> 'legacy_balance_unique_item_number',
             t.moss_transaction_uuid::text,
             (e.additional_info ->> 'legacy_balance_sub_row_number')::integer,
             t.moss_transaction_state, t.transaction_type, t.payment_date, t.booking_date,
             b.legacy_amount_excl_vat, e.signed_expense_base_amount, coalesce(t.currency, 'EUR'),
             b.legacy_original_amount_excl_vat, e.signed_expense_transaction_amount, t.currency_original,
             (t.other_moss_columns ->> 'Conversion Rate')::numeric,
             t.conversion_rate_including_fees, t.fees_amount, t.payment_fee,
             t.total_amount_excluding_fees,
             t.supplier_account_number, t.additional_info ->> 'legacy_supplier_name',
             e.additional_info ->> 'legacy_balance_account_number',
             coalesce(la.name, ''),
             e.other_moss_columns ->> 'Category',
             t.moss_balance_account_number, t.cash_in_transit_account_number,
             t.other_moss_columns ->> 'Reason for Purchase', coalesce(e.expense_posting_text, ''),
             t.recipient_iban, t.recipient_bic, t.payment_reference, t.invoice_number,
             t.payout_team_name, t.payout_user_name, coalesce(b.client_number, ''), t.first_export_date,
             '',
             t.moss_invoice_uuid::text, t.moss_reimbursement_uuid::text,
             t.other_moss_columns ->> 'Moss Attachment URL',
             e.created_at, e.updated_at
      FROM moss_expenses e
      JOIN moss_transactions t ON t.id = e.moss_transaction_id
      LEFT JOIN wsjrdp_ledger_accounts la ON la.number = e.additional_info ->> 'legacy_balance_account_number'
      JOIN LATERAL (
             SELECT min(comment) AS comment,
                    min(other_moss_columns ->> 'Client Number') AS client_number,
                    (array_agg(additional_info ORDER BY booking_unique_item_number))[1] AS additional_info,
                    min(contribution_subject_id) AS contribution_subject_id,
                    min(contribution_subject_type) AS contribution_subject_type,
                    -- the mirrors may be signed (written by `up`) or unsigned (the
                    -- reimbursement export's per-split figures, as imported): sum
                    -- their magnitudes, sign like the expense
                    sign(e.signed_expense_base_amount)
                      * sum(abs(NULLIF(other_moss_columns ->> 'Amount (excl. VAT)', '')::numeric)) AS legacy_amount_excl_vat,
                    sign(e.signed_expense_base_amount)
                      * sum(abs(NULLIF(other_moss_columns ->> 'Original Amount (excl. VAT)', '')::numeric)) AS legacy_original_amount_excl_vat
               FROM moss_bookings WHERE moss_expense_id = e.id) b ON true
      WHERE t.type = 'MossReimbursement'

      UNION ALL
      -- invoice and top-up: one row per booking (an invoice's lines are its bookings)
      SELECT t.fin_account_id, b.contribution_subject_id, b.contribution_subject_type,
             b.comment, t.status,
             b.additional_info - 'legacy_balance_unique_item_number' - 'legacy_balance_sub_row_number',
             b.additional_info ->> 'legacy_balance_unique_item_number',
             t.moss_transaction_uuid::text,
             (b.additional_info ->> 'legacy_balance_sub_row_number')::integer,
             t.moss_transaction_state, t.transaction_type, t.payment_date, t.booking_date,
             NULLIF(b.other_moss_columns ->> 'Amount (excl. VAT)', '')::numeric,
             b.signed_base_amount, coalesce(t.currency, 'EUR'),
             NULLIF(b.other_moss_columns ->> 'Original Amount (excl. VAT)', '')::numeric,
             b.signed_transaction_amount, t.currency_original,
             (t.other_moss_columns ->> 'Conversion Rate')::numeric,
             t.conversion_rate_including_fees, t.fees_amount, t.payment_fee,
             t.total_amount_excluding_fees,
             t.supplier_account_number, t.additional_info ->> 'legacy_supplier_name',
             b.account_number, coalesce(la.name, ''),
             b.other_moss_columns ->> 'Category',
             t.moss_balance_account_number, t.cash_in_transit_account_number,
             t.other_moss_columns ->> 'Reason for Purchase', b.booking_posting_text,
             t.recipient_iban, t.recipient_bic, t.payment_reference, t.invoice_number,
             t.payout_team_name, t.payout_user_name, coalesce(b.other_moss_columns ->> 'Client Number', ''), t.first_export_date,
             '',
             t.moss_invoice_uuid::text, t.moss_reimbursement_uuid::text,
             t.other_moss_columns ->> 'Moss Attachment URL',
             b.created_at, b.updated_at
      FROM moss_bookings b
      JOIN moss_transactions t ON t.id = b.moss_transaction_id
      JOIN moss_expenses e ON e.id = b.moss_expense_id
      LEFT JOIN wsjrdp_ledger_accounts la ON la.number = b.account_number
      WHERE t.type IN ('MossInvoice', 'MossTopUp')
    SQL
  end

  def restore_contribution_link
    add_column :accounting_entries, :moss_balance_movement_id, :bigint, null: true
    # The legacy id is rebuilt purely by (transaction uuid, sub_row_number),
    # both of which `up` preserved on the level the flat row came from.
    execute <<~SQL
      UPDATE accounting_entries ae
         SET moss_balance_movement_id = m.id
        FROM moss_bookings b
        JOIN moss_transactions t ON t.id = b.moss_transaction_id
        JOIN moss_expenses e ON e.id = b.moss_expense_id
        JOIN moss_balance_movements m
          ON m.moss_transaction_id = t.moss_transaction_uuid::text
         AND m.sub_row_number = CASE WHEN t.type = 'MossReimbursement'
                                     THEN e.expense_number
                                     ELSE (b.additional_info ->> 'legacy_balance_sub_row_number')::integer END
       WHERE ae.moss_booking_id = b.id
    SQL
    remove_column :accounting_entries, :camt_transaction_link_meta
    remove_column :accounting_entries, :moss_booking_link_meta
    remove_reference :accounting_entries, :moss_booking, foreign_key: {to_table: :moss_bookings}
  end
end
