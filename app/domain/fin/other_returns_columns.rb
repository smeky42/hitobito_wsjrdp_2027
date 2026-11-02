# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Columns of the section "Weitere Rückläufer" of the Rückläufer tab
# (/fin/payments/returns): every payment other than one of our direct debits
# that came back (Fin::PaymentQueries.other_returns), one bank transaction per
# row, with what came back (return_kind) and from whom.
module Fin::OtherReturnsColumns
  # The other party: the payee of a credit transfer we sent or of a direct debit
  # we were charged, else the payer.
  COUNTERPARTY_SQL = "CASE WHEN wsjrdp_camt_transactions.return_kind IN ('credit_transfer', 'received_direct_debit') " \
    "THEN wsjrdp_camt_transactions.cdtr_name ELSE wsjrdp_camt_transactions.dbtr_name END"

  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "orcol") do |c|
    c.column key: "date", abbr: "d", label: "Datum", width: "6.5rem", tabular_nums: true,
      sort: "COALESCE(wsjrdp_camt_transactions.booking_date, wsjrdp_camt_transactions.value_date)",
      sort_first: "desc", default: true
    c.column key: "kind", abbr: "k", label: "Art", width: "10rem",
      sort: "wsjrdp_camt_transactions.return_kind", default: true
    c.column key: "amount", abbr: "a", label: "Betrag", numeric: true, width: "7rem", tabular_nums: true,
      sort: "wsjrdp_camt_transactions.signed_base_amount", default: true
    c.column key: "counterparty", abbr: "cp", label: "Gegenpartei", width: "10rem", target_width: "16rem", grow: 1,
      sort: "LOWER(#{COUNTERPARTY_SQL})", default: true
    c.column key: "reason", abbr: "rs", label: "Grund", width: "10rem", target_width: "24rem", grow: 2,
      sort: "wsjrdp_camt_transactions.return_reason", default: true
    c.column key: "code", abbr: "c", label: "Code", width: "9rem",
      header_tooltip: "ISO Bank Transaction Code (Family+SubFamily) und GVC laut Kontoauszug",
      sort: "wsjrdp_camt_transactions.gvc", default: true
    c.column key: "description", abbr: "ds", label: "Verwendungszweck", width: "14rem",
      sort: "LOWER(wsjrdp_camt_transactions.description)"
    c.column key: "id", abbr: "id", label: "ID", numeric: true, width: "4.5rem",
      sort: "wsjrdp_camt_transactions.id", sort_first: "desc"
  end
end
