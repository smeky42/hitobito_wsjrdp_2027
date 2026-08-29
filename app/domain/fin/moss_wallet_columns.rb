# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# THE columns of the Moss WALLET statement (fin/wsjrdp_fin_accounts#show for the
# account with transaction_type "MossBalanceMovement"), described once
# (doc/wsjrdp/expandable_table.md).
#
# The rows there are MossBookings (L3, the grain DATEV books at), not
# transactions -- which is why this is a module of its own next to
# Fin::MossTransactionsColumns: the two tables show different rows of the same
# data, so they sort on different tables (`value_date` is the TRANSACTION's
# payment_date reached through the join, `signed_base_amount` the BOOKING's own
# share) and a shared description would have to carry both.
#
# Four columns, all visible by default: a wallet statement is read line by line,
# so there is nothing to hide -- the picker exists to REORDER them and to switch
# one off for a narrow screen. The eye that opens the booking's detail page is
# the widget's `action`, not a column: it is never sorted, never hidden and
# never reordered.
module Fin::MossWalletColumns
  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "mwcol") do |c|
    c.column key: "value_date", abbr: "vdt", label: "Valuta", width: "6rem",
      sort: "moss_transactions.payment_date", default: true
    c.column key: "kind", abbr: "knd", label: "Art", width: "7rem",
      sort: "moss_transactions.type", default: true
    c.column key: "signed_base_amount", abbr: "amt", label: "Betrag", numeric: true,
      width: "6rem", sort: "moss_bookings.signed_base_amount", default: true
    # No width: the description takes whatever the other three leave, and it is
    # the one column that wants every pixel (name, party, tags, Buchungstext,
    # comments, the linked contribution bookings and their action buttons).
    # No sort either -- what it shows is composed from three levels and has no
    # single ORDER BY behind it.
    c.column key: "description", abbr: "dsc", label: "Beschreibung", default: true
  end

  def self.codec = COLUMNS.codec

  def self.default_keys = COLUMNS.default_keys

  def self.sort_expressions = COLUMNS.sort_expressions
end
