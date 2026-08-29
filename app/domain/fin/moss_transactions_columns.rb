# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# THE columns of the Moss transactions table (all four kinds), described once
# (doc/wsjrdp/expandable_table.md). Declaration order is the table's column
# order: the default-visible columns first, then the ones the picker offers.
#
# The aggregate columns (Buchungen, Sachkonten, Kostenstellen, Händler/Empfänger,
# DATEV) are derived from the eager-loaded expenses + bookings and therefore
# carry no `sort:` -- they cannot be expressed as an ORDER BY on
# moss_transactions.
module Fin::MossTransactionsColumns
  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "mtcol") do |c|
    # Widths are cut to the content they hold (a dd.mm.yyyy date, the widest
    # kind chip, an amount with its currency plus a foreign-currency second
    # line), and the description carries NO width: in the widget's fixed table
    # layout the one width-less column absorbs the leftover space, whereas a
    # table whose columns are all fixed spreads it over every column -- which
    # made Art and Betrag grow with the window although their content does not.
    c.column key: "payment_date", abbr: "pdt", label: "Datum", width: "6rem",
      sort: "moss_transactions.payment_date", default: true
    c.column key: "kind", abbr: "knd", label: "Art", width: "7rem",
      sort: "moss_transactions.type", default: true
    c.column key: "signed_total_base_amount", abbr: "amt", label: "Betrag", numeric: true,
      width: "7.5rem", sort: "moss_transactions.signed_total_base_amount", default: true
    c.column key: "description", abbr: "dsc", label: "Beschreibung", default: true
    c.column key: "cost_centers", abbr: "cc", label: "Kostenstellen", width: "12rem",
      default: true
    c.column key: "account_numbers", abbr: "acc", label: "Sachkonten", width: "14rem",
      default: true
    c.column key: "party", abbr: "pty", label: "Händler / Empfänger", width: "13rem"
    # The person columns of the unified model, one per role -- the card holder
    # (card payments), the payee and whoever paid out (invoices and
    # reimbursements), the sender of a top-up. "Händler / Empfänger" above picks
    # the one role that fits the row's kind; the kind tabs offer the fitting
    # column directly (Fin::MossTransactionsController::KIND_COLUMNS).
    c.column key: "card_holder_name", abbr: "ch", label: "Karteninhaber", width: "11rem",
      sort: "moss_transactions.card_holder_name"
    c.column key: "recipient_name", abbr: "rcp", label: "Empfänger", width: "13rem",
      sort: "moss_transactions.recipient_name"
    c.column key: "payout_user_name", abbr: "pu", label: "Auszahlung durch", width: "11rem",
      sort: "moss_transactions.payout_user_name"
    c.column key: "top_up_sender", abbr: "snd", label: "Absender", width: "13rem",
      sort: "moss_transactions.top_up_sender"
    c.column key: "supplier_account_number", abbr: "sup", label: "Kreditor", width: "12rem",
      sort: "moss_transactions.supplier_account_number"
    # Buchungen holds a one- or two-digit count, so it is the narrowest column
    # of the table and carries the SHORT header "Bu." -- the full word would be
    # four times as wide as anything below it and would push the description
    # out of the row. (The widget's header renders the label alone; a `title:`
    # for the long word would have to be added to
    # Wsjrdp::ExpandableTableColumn#to_table_column AND to the `%th` of
    # shared/wsjrdp/_expandable_table first. The column picker lists the same
    # label and therefore reads "Bu." as well.)
    c.column key: "bookings_count", abbr: "nb", label: "Bu.", numeric: true, width: "3rem"
    c.column key: "booking_date", abbr: "bdt", label: "Buchungsdatum", width: "7rem",
      sort: "moss_transactions.booking_date"
    c.column key: "approval_date", abbr: "adt", label: "Freigegeben am", width: "7rem",
      sort: "moss_transactions.approval_date"
    c.column key: "moss_transaction_state", abbr: "st", label: "Status (Moss)", width: "8rem",
      sort: "moss_transactions.moss_transaction_state"
    c.column key: "invoice_number", abbr: "inv", label: "Belegnummer", width: "9rem",
      sort: "moss_transactions.invoice_number"
    c.column key: "currency_original", abbr: "cur", label: "Original-Währung", width: "6rem",
      sort: "moss_transactions.currency_original"
    c.column key: "datev", abbr: "dv", label: "DATEV", width: "8rem"
  end

  def self.codec = COLUMNS.codec

  def self.default_keys = COLUMNS.default_keys

  def self.sort_expressions = COLUMNS.sort_expressions
end
