# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# THE columns of the Moss bookings tables -- the Buchungen tab
# (fin/moss_bookings#index) and the bookings of one transaction or expense on
# its page (fin/moss_bookings/_parent_table) --, described once
# (doc/wsjrdp/expandable_table.md).
#
# The rows there are MossBookings (L3, the grain DATEV books at), not
# transactions -- which is why this is a module of its own next to
# Fin::MossTransactionsColumns: the two tables show different rows of the same
# data, so they sort on different tables (`booking_date` is the TRANSACTION's
# column reached through the join, `signed_base_amount` the BOOKING's own share)
# and a shared description would have to carry both.
#
# The default columns come first, then the ones the picker offers. The
# transaction-level ones (party, persons, Kreditor, dates, status) show the
# booking's payment, the same words as the transactions table. The booking's
# own page is reached through the detail's header line, not a column.
module Fin::MossBookingsColumns
  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "mwcol") do |c|
    # Buchungsdatum is the day the payment was booked in the wallet -- the
    # booking has no date of its own, so cell and ORDER BY alike read the
    # transaction's column (MossBooking#value_date is the same day).
    c.column key: "booking_date", abbr: "bdt", label: "Buchungsdatum", short_label: "Buchung",
      width: "7rem", target_width: "9rem", sort: "moss_transactions.booking_date", default: true
    c.column key: "kind", abbr: "knd", label: "Art", width: "7rem",
      sort: "moss_transactions.type", default: true
    c.column key: "signed_base_amount", abbr: "amt", label: "Betrag", numeric: true, sort_first: "desc",
      width: "6.5rem", sort: "moss_bookings.signed_base_amount", default: true
    # The description takes whatever the others leave once the date has its
    # target width (grow), and it is the one column that wants every pixel
    # (name, party, tags, Buchungstext, comments, the linked contribution
    # bookings and their action buttons). No sort -- what it shows is composed
    # from three levels and has no single ORDER BY behind it.
    c.column key: "description", abbr: "dsc", label: "Beschreibung", width: "8rem", grow: 1, default: true
    # The booking's own accounting: number plus name, as in the transactions
    # table's aggregate columns -- here one value per row, so they sort.
    c.column key: "cost_center_number", abbr: "cc", label: "Kostenstelle", width: "10rem",
      sort: "moss_bookings.cost_center_number", default: true
    c.column key: "account_number", abbr: "acc", label: "Sachkonto", width: "11.5rem",
      sort: "moss_bookings.account_number", default: true
    c.column key: "sphere_number", abbr: "sph", label: "Sphäre", width: "5rem",
      sort: "moss_bookings.sphere_number"
    c.column key: "party", abbr: "pty", label: "Händler / Empfänger", width: "13rem"
    c.column key: "card_holder_name", abbr: "ch", label: "Karteninhaber", width: "11rem",
      sort: "moss_transactions.card_holder_name"
    c.column key: "recipient_name", abbr: "rcp", label: "Empfänger", width: "13rem",
      sort: "moss_transactions.recipient_name"
    c.column key: "supplier_account_number", abbr: "sup", label: "Kreditor", width: "12rem",
      sort: "moss_transactions.supplier_account_number"
    c.column key: "invoice_number", abbr: "inv", label: "Belegnummer", width: "9rem",
      sort: "moss_transactions.invoice_number"
    c.column key: "payment_date", abbr: "pdt", label: "Zahlungsdatum", width: "7rem",
      sort: "moss_transactions.payment_date"
    c.column key: "moss_transaction_state", abbr: "st", label: "Status (Moss)", width: "8rem",
      sort: "moss_transactions.moss_transaction_state"
    # Whether the booking's expense leg is linked to its DATEV booking.
    c.column key: "datev", abbr: "dv", label: "DATEV", width: "6rem"
  end

  # The columns of a table of ONE transaction's or expense's bookings: date
  # and kind, the same in every row, left out.
  PARENT_DEFAULT_KEYS = %w[signed_base_amount description cost_center_number account_number].freeze

  # What the cells read per booking -- the payment (kind, party, currency), the
  # expense (a reimbursement's own name and text), the person a booking is
  # assigned to and the linked contribution bookings with their person.
  ROW_PRELOADS = [:moss_transaction, :moss_expense, :contribution_subject, {accounting_entries: :subject}].freeze

  # The rows of a bookings table over `source` (which joins moss_transactions,
  # the date's and the kind's table).
  def self.rows(state, source, **options)
    Wsjrdp::ExpandableTableRows.new(state, source, sort: sort_expressions, preload: ROW_PRELOADS, **options)
  end

  def self.codec = COLUMNS.codec

  def self.default_keys = COLUMNS.default_keys

  def self.sort_expressions = COLUMNS.sort_expressions
end
