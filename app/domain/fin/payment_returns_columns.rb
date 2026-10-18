# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Columns of the Rückläufer list (/fin/payments/returns): one return (a bank
# transaction with a return reason) per row over Fin::PaymentQueries.returns,
# with the debit and the order it belongs to and the accounting entry booked
# for it.
module Fin::PaymentReturnsColumns
  # The return's processing status (WsjrdpCamtTransaction#return_status) in SQL.
  STATUS_SQL = "COALESCE(NULLIF(wsjrdp_camt_transactions.additional_info->>'return_debit_status', ''), 'in_review')"

  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "prcol") do |c|
    c.column key: "person", abbr: "p", label: "Person", width: "9rem", target_width: "13rem", grow: 1,
      sort: "LOWER(people.last_name || ' ' || people.first_name)", default: true
    c.column key: "date", abbr: "d", label: "Datum", width: "6.5rem", tabular_nums: true,
      sort: "COALESCE(wsjrdp_camt_transactions.booking_date, wsjrdp_camt_transactions.value_date)",
      sort_first: "desc", default: true
    c.column key: "amount", abbr: "a", label: "Betrag", numeric: true, width: "7rem", tabular_nums: true,
      sort: "wsjrdp_camt_transactions.signed_base_amount", default: true
    c.column key: "reason", abbr: "rs", label: "Grund", width: "10rem", target_width: "30rem", grow: 4,
      sort: "wsjrdp_camt_transactions.return_reason", default: true
    c.column key: "debit", abbr: "db", label: "Einzug", width: "8rem", narrow: false,
      header_tooltip: "Der Einzug, auf den die Kontobewegung verweist; ohne Verweis der mit derselben End-to-End-ID, sonst mit derselben Mandatsreferenz",
      sort: "notice.collection_date", sort_first: "desc", default: true
    c.column key: "order", abbr: "o", label: "Auftrag", numeric: true, width: "5rem", narrow: false,
      sort: Fin::PaymentQueries::RETURN_ORDER_SQL, sort_first: "desc", default: true
    c.column key: "entry", abbr: "en", label: "Beitragsbuchung", header_label: "Beitrags-<br>buchung".html_safe,
      width: "5.5rem", header_align: "center", narrow: false,
      header_tooltip: "Die Buchung zur Rücklastschrift auf dem Beitragskonto der Person",
      sort: "(entry.id IS NOT NULL)", default: true
    c.column key: "status", abbr: "st", label: "Bearbeitung", width: "9.5rem", header_align: "center",
      sort: STATUS_SQL, default: true
    c.column key: "endtoend_id", abbr: "ee", label: "End-to-End-ID", width: "13rem",
      sort: "wsjrdp_camt_transactions.endtoend_id"
    c.column key: "mandate_id", abbr: "md", label: "Mandatsreferenz", width: "10rem",
      sort: "wsjrdp_camt_transactions.mandate_id"
    c.column key: "description", abbr: "ds", label: "Verwendungszweck", width: "14rem",
      sort: "LOWER(wsjrdp_camt_transactions.description)"
    c.column key: "id", abbr: "id", label: "ID", numeric: true, width: "4.5rem",
      sort: "wsjrdp_camt_transactions.id", sort_first: "desc"
  end
end
