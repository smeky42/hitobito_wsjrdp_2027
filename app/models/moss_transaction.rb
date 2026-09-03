# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# L1 of the unified Moss model: ONE row per Moss transaction. A card transaction
# is a payment; an invoice, reimbursement or top-up has exactly one payment in
# Moss, not modelled as a row of its own. See
# doc/plans/2026-08_moss-transaction-unification.md.
#
#   MossTransaction (this class, STI base -- never instantiated directly)
#     MossCardTransaction   a card payment
#     MossInvoice           an incoming invoice paid from the wallet (or directly)
#     MossReimbursement     a payout bundling several expenses (-> N MossExpenses)
#     MossTopUp             money moved INTO the wallet (positive amount)
#
# Because the expense level of a reimbursement is only a bracket inside that one
# payment, the TOTAL, the currencies and the exchange rate live here and nowhere
# else; the amounts themselves exist at all three levels and must agree:
#
#   signed_total_base_amount == SUM(expenses) == SUM(bookings)
#
# Everything Moss does not model per split (creditor, wallet/transit accounts,
# dates, the reconciliation links) is a column of this table.
class MossTransaction < ActiveRecord::Base
  include ActionView::Helpers::NumberHelper
  include ActionView::Helpers::TextHelper

  # Moss record pages. Every URL is DERIVED from a stored uuid -- Moss URLs are
  # stable, so storing them would only add a second source of truth. The
  # subclasses add the kind-specific ones (invoice, reimbursement).
  MOSS_APP_URL = "https://getmoss.com/app"

  # STI: `type` holds the class name; there is no `source` column, and
  # `expense_type` is generated from `type` in the database.
  self.inheritance_column = "type"

  belongs_to :fin_account, optional: true, class_name: "WsjrdpFinAccount"

  # The person the money is paid to (Erstattungsempfaenger). A different role
  # from the booking-level contribution_subject: this is who received the
  # payment, that is whose Beitrag a booking concerns.
  belongs_to :recipient, optional: true, class_name: "Person"

  # Step 2 of the Moss->DATEV chain (creditor -> Moss balance 36100), posted once
  # per transaction with the transaction total.
  belongs_to :clearing_datev_booking, optional: true, class_name: "DatevBooking",
    inverse_of: :moss_transaction_as_clearing

  # Top-ups only: the bank transfer that funded the wallet. The export names
  # the funding account only truncated (`top_up_sender`), so this link is
  # matched on amount + date.
  belongs_to :camt_transaction, optional: true, class_name: "WsjrdpCamtTransaction"

  # The chain accounts, matched on their unique `number`; the generated
  # `*_type` columns carry the polymorphic target class (see the migration).
  belongs_to :supplier_account, polymorphic: true, optional: true,
    foreign_key: :supplier_account_number, primary_key: :number
  belongs_to :moss_balance_account, polymorphic: true, optional: true,
    foreign_key: :moss_balance_account_number, primary_key: :number
  belongs_to :cash_in_transit_account, polymorphic: true, optional: true,
    foreign_key: :cash_in_transit_account_number, primary_key: :number

  has_many :expenses, -> { order(:expense_number) },
    inverse_of: :moss_transaction,
    class_name: "MossExpense",
    dependent: :destroy
  has_many :bookings,
    inverse_of: :moss_transaction,
    class_name: "MossBooking",
    dependent: :destroy

  validates :type, inclusion: {in: %w[MossCardTransaction MossInvoice MossReimbursement MossTopUp]}

  # --- other_moss_columns ----------------------------------------------------
  # Raw Moss fields without a column, kept UNDER THEIR CSV HEADER; these
  # accessors are the only place the header is mapped to a snake_case name.
  # The amount / currency / rate mirrors (also under their headers) have no
  # accessor: the house columns carry them.
  OTHER_MOSS_TEXT_COLUMNS = {
    # card export: the payment ...
    reason_for_purchase: "Reason for Purchase",
    general_transaction_type: "General Transaction Type",
    sage_payment_type: "Sage Payment Type",
    sage_transaction_type: "Sage Transaction Type",
    supplier_vat_id: "Supplier Vat ID",
    # ... and its expense: in Moss the card header IS the expense
    # (CardTransactionMetadata), so these are transaction facts, not expense
    # facts (the VAT fields of a card row live on the booking)
    invoice_file_name: "Invoice File Name",
    # the card holder's name as printed on the card (the column
    # card_holder_name holds the CSV Cardholder, the full name) and the two
    # constant labels of the card export
    card_holder_name_on_card: "Card Holder Name",
    card_holder_label: "Card Holder Label",
    card_label: "Card Label",
    card_acceptor_name: "Card Acceptor Name",
    airline_ticket_number: "Airline Ticket Number",
    is_prepayment: "Is Prepayment?",
    number_of_months_in_release_plan: "Number of Months in Release Plan",
    # invoice export: the invoice's payment status, terms and reviewers --
    # header facts in Moss (InvoiceMetadata); Invoice File Name, Is
    # Prepayment? and the release plan share their headers with the card
    # export above (Invoice Status is the column invoice_status)
    invoice_payment_status: "Invoice Payment Status",
    general_invoice_type: "General Invoice Type",
    payment_term_description: "Payment term - Description",
    payment_term_number: "Payment term - Number",
    discount_1_percentage: "Discount 1 percentage",
    discount_2_percentage: "Discount 2 percentage",
    reviewed_by: "Reviewed by",
    verified_by_name: "Verified By Name",
    verifier_names: "Verifier Names",
    # balance-movements export (Category is a per-row value and lives on the
    # expense / booking, Client Number on the booking)
    moss_attachment_url: "Moss Attachment URL",
    # reimbursement export: facts about the whole payment (constant per
    # reimbursement); the Name is also the column transaction_name, the
    # description is the transaction_posting_text, the creation date a column
    reimbursement_payment_status: "Reimbursement Payment Status",
    reimbursement_name: "Reimbursement Name"
  }.freeze

  OTHER_MOSS_DATE_COLUMNS = {
    # card and invoice exports
    prepayment_start_date: "Prepayment Start Date",
    prepayment_end_date: "Prepayment End Date",
    # invoice export
    net_due_date: "Net Due Date",
    discount_1_due_date: "Discount 1 due date",
    discount_2_due_date: "Discount 2 due date",
    last_reviewed: "Last reviewed"
  }.freeze

  OTHER_MOSS_TEXT_COLUMNS.each do |name, key|
    define_method(name) { other_moss_columns[key].presence }
  end

  OTHER_MOSS_DATE_COLUMNS.each do |name, key|
    define_method(name) { other_moss_date(key) }
  end

  scope :cards, -> { where(type: "MossCardTransaction") }
  scope :balance_movements, -> { where(type: %w[MossInvoice MossReimbursement MossTopUp]) }

  # --- money -----------------------------------------------------------------

  # The signed EUR amount, under the name the shared statement view uses.
  def amount_eur = signed_total_base_amount

  def amount_cents = (signed_total_base_amount * 100).round

  def amount_eur_display
    number_to_currency(signed_total_base_amount, separator: ",", delimiter: ".", format: "%n")
  end

  # True when the transaction is in a foreign currency; then the DATEV match runs
  # on the transaction amount, never on EUR (each side converts differently).
  def foreign_currency? = currency_original.present? && currency_original != currency

  # --- reconciliation --------------------------------------------------------

  # The sum invariant, as a query: use it in specs and after an import.
  def sum_invariant_holds?
    signed_total_base_amount == expenses.sum(:signed_expense_base_amount) &&
      signed_total_base_amount == bookings.sum(:signed_base_amount)
  end

  # Settled or booked outside the Moss->DATEV export path; both may be true.
  def manually_handled? = manually_paid? || manually_booked?

  # --- Moss URLs -------------------------------------------------------------

  # The transaction's own record page. Subclasses override where Moss uses a
  # different section (the balance kinds live under /export/balance-movements).
  def moss_record_url = "#{MOSS_APP_URL}/transactions/all/#{moss_transaction_uuid}"

  def moss_export_url = "#{MOSS_APP_URL}/export/balance-movements/#{moss_transaction_uuid}"

  # --- display ---------------------------------------------------------------

  # The "name" and the Buchungstext of the payment as the FIN views show them,
  # per kind (the subclasses override): a reimbursement's title, a card
  # payment's merchant, an invoice's number, a top-up's "Einzahlung"; the text
  # is the Buchungstext, a top-up's its funding account.
  def display_name = nil

  def display_text = transaction_posting_text

  # "name – text", whichever exist; the SEPA reference as the last resort.
  def description
    [display_name, display_text].compact_blank.join(" – ").presence || payment_reference
  end

  def value_date = payment_date

  def link_name(length: 80)
    pre = "[#{id}] "
    post = " (#{amount_eur_display})"
    length -= (pre.size + post.size)
    "#{pre}#{truncate(description.to_s, length: length)}#{post}"
  end

  private

  def other_moss_date(key)
    value = other_moss_columns[key]
    Date.parse(value) if value.present?
  rescue Date::Error
    nil
  end
end
