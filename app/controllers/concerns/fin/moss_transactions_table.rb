# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The rows of a Moss transactions table (fin/moss_transactions/_table): the
# Transaktionen tabs (Fin::MossTransactionsController) and the Moss wallet's
# page (Fin::WsjrdpFinAccountsController). The host declares the table's
# policy and answers `transactions_table_state`; it may narrow the rows with
# `moss_transactions_base` and pin a kind with `current_kind`.
module Fin::MossTransactionsTable
  extend ActiveSupport::Concern

  included do
    helper_method :transactions
  end

  # The listing: the de-duplicated, filtered relation handed to
  # Wsjrdp::ExpandableTableRows for sorting, pagination and the sum. Expenses and
  # bookings are preloaded for the aggregate columns AND the expandable detail.
  def transactions
    @transactions ||= Wsjrdp::ExpandableTableRows.new(transactions_table_state,
      distinct_transactions,
      sort: Fin::MossTransactionsColumns.sort_expressions,
      sum: :signed_total_base_amount,
      preload: transaction_preloads,
      tiebreaker: "moss_transactions.id")
  end

  private

  # The transactions the table starts from, before the filter: all of them.
  def moss_transactions_base = MossTransaction.all

  # The kind (STI type) the table is pinned to, nil for every kind.
  def current_kind = nil

  # The columns that read a transaction's expenses and bookings
  # (Fin::MossTransactionsHelper#moss_transaction_bookings).
  AGGREGATE_COLUMNS = %w[cost_centers account_numbers bookings_count datev].freeze

  # What the page reaches for per row: the expenses with their bookings feed the
  # aggregate columns, the expense sub-rows of a reimbursement
  # (Fin::MossExpenseRowsHelper) and the person side of the description cell
  # (Fin::MossTransactionsHelper#moss_transaction_subject_links). A tab on which
  # a reimbursement can appear therefore always preloads them -- the sub-rows
  # read them whatever the visible columns are; on the other kind tabs they are
  # loaded only while a column that reads them is visible, and the person side
  # (person, contribution bookings) only with the description, so a
  # slimmed-down column set does not load hundreds of bookings for nothing
  # (Bullet flags both the missing and the unused preload). The detail is lazy
  # and loads its own records (#show).
  def transaction_preloads
    return [] unless expense_rows_possible? || person_links_visible? ||
      transactions_table_state.visible_column_keys.intersect?(AGGREGATE_COLUMNS)

    [{expenses: {bookings: person_links_visible? ? BOOKING_LINK_PRELOADS : []}}]
  end

  # What the description cell's linking blocks read per booking
  # (fin/moss_bookings/_subject_links).
  BOOKING_LINK_PRELOADS = [:contribution_subject, {accounting_entries: :subject}].freeze

  # The description column carries the person side of every booking.
  def person_links_visible?
    transactions_table_state.visible_column_keys.include?("description")
  end

  # Can a reimbursement -- the one kind that brings expense sub-rows -- be on
  # this tab? The general tab lists every kind, the Erstattungen tab that one.
  def expense_rows_possible?
    current_kind.nil? || current_kind == "MossReimbursement"
  end

  # The filtered scope LEFT JOINs the expenses and their bookings (so
  # expense- and booking-level filters can match), which would show a
  # transaction with several matching bookings more than once. The listing
  # therefore selects the matching transaction ids and re-queries
  # moss_transactions by id, so the sort and the paging see one row per
  # transaction. The joins themselves are NOT repeated here -- they belong to
  # the schema's base relation and are merged in by
  # Wsjrdp::Filtering::FilterSchema#compile.
  def distinct_transactions
    MossTransaction.where(id: transactions_table_state.filter.scope(moss_transactions_base)
      .reselect(MossTransaction.arel_table[:id]))
  end
end
