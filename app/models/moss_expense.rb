# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# L2 of the unified Moss model: one row per EXPENSE (one purchase, with its
# receipt attached).
#
#   MossExpense (this class, STI base)
#     MossCardTransactionExpense   exactly one per card payment
#     MossInvoiceExpense           exactly one per invoice
#     MossReimbursementExpense     N per reimbursement -- the only real middle level
#     MossTopUpExpense             exactly one per top-up
#
# For every kind except reimbursements the expense is a SHELL: a 1:1 bracket
# around the transaction that exists so that the three levels are uniform and
# the sum invariant can be checked at each of them. It carries nothing
# kind-specific -- in Moss's own model a card payment or an invoice has no
# middle level, the header is the expense, so the merchant, the receipt file,
# the invoice's dates and terms are all transaction columns / keys. In the
# FIN web UI only a reimbursement's expenses are shown; for the other kinds
# the level collapses into the transaction.
#
# NOT here: the creditor and the currencies/exchange rate (they belong to the one
# payment -> L1) and the split dimensions Sachkonto/Kostenstelle/Sphaere/
# Buchungstext (they differ per split -> L3).
class MossExpense < ActiveRecord::Base
  include ActionView::Helpers::NumberHelper

  self.inheritance_column = "type"

  belongs_to :moss_transaction, inverse_of: :expenses

  has_many :bookings, -> { order(:booking_unique_item_number) },
    inverse_of: :moss_expense,
    class_name: "MossBooking",
    foreign_key: :moss_expense_id,
    dependent: :destroy

  validates :type, inclusion: {in: %w[MossCardTransactionExpense MossInvoiceExpense
    MossReimbursementExpense MossTopUpExpense]}

  # The approval is a property of the associated Moss transaction.
  delegate :approver_name, :approval_date, to: :moss_transaction, allow_nil: true

  # --- other_moss_columns ----------------------------------------------------
  # Everything the reimbursement export carries per expense
  # that has no column of its own is kept in other_moss_columns UNDER
  # ITS MOSS HEADER (the importer stores a key only when the cell has
  # a value). These accessors name them.  The shell rows of the other
  # kinds carry no keys; the migration's own scaffolding lives in
  # additional_info and has no accessor on purpose.
  OTHER_MOSS_TEXT_COLUMNS = {
    # reimbursement export
    attached_file_name: "Attached File Name",
    km_expense_type: "KM Expense Type",
    start_location: "Start Location",
    destination_location: "Destination Location",
    travel_route: "Travel Route",
    trip_type: "Trip Type",
    trip_distance_in_unit: "Trip Distance In Unit",
    reimbursable_distance_in_unit: "Reimbursable Distance In Unit",
    commute_deduction_in_unit: "Commute Deduction In Unit",
    distance_unit: "Distance Unit",
    vehicle_type: "Vehicle Type"
  }.freeze

  OTHER_MOSS_TEXT_COLUMNS.each do |name, key|
    define_method(name) { other_moss_columns[key].presence }
  end

  # The signed EUR amount, under the name the shared statement view uses.
  def amount_eur = signed_expense_base_amount

  def amount_cents = (signed_expense_base_amount * 100).round

  def amount_eur_display
    number_to_currency(signed_expense_base_amount, separator: ",", delimiter: ".", format: "%n")
  end

  # An expense is "split" when Moss booked it against more than one account /
  # cost center; only then does the middle level carry information a single
  # booking would not.
  def split? = bookings.size > 1

  def sum_invariant_holds?
    signed_expense_base_amount == bookings.sum(:signed_base_amount)
  end

  # The expense's name (the reimbursement export's Expense Name: the merchant
  # or the route) and its Buchungstext; a shell row has neither.
  def display_name = expense_name

  def display_text = expense_posting_text

  def description = [display_name, display_text].compact_blank.join(" – ")
end
