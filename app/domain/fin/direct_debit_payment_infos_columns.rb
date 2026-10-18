# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Columns of the Sammler tables: the list (/fin/direct_debit_payment_infos)
# and the Sammler of an order (fin/payment_orders/_head, without Auftrag). One
# direct debit payment info (a Sammler: one collection date and sequence type
# of an order) per row over Fin::PaymentQueries.payment_infos, so every column
# sorts by SQL; a row opens the Sammler's page
# (Fin::DirectDebitPaymentInfosController). Where the table would scroll
# sideways the ids give way (narrow: false).
module Fin::DirectDebitPaymentInfosColumns
  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "dpcol") do |c|
    c.column key: "order", abbr: "o", label: "Auftrag", numeric: true, width: "5rem", narrow: false,
      sort: "wsjrdp_direct_debit_payment_infos.payment_initiation_id", sort_first: "desc", default: true
    c.column key: "identification", abbr: "pid", label: "PmtInf-ID", width: "12rem", narrow: false,
      sort: "wsjrdp_direct_debit_payment_infos.payment_information_identification"
    c.column key: "collection_date", abbr: "cd", label: "Einzug", width: "6.5rem", tabular_nums: true,
      sort: "wsjrdp_direct_debit_payment_infos.requested_collection_date", sort_first: "desc", default: true
    c.column key: "sequence", abbr: "seq", label: "Sequenz", width: "5rem",
      sort: "wsjrdp_direct_debit_payment_infos.debit_sequence_type", default: true
    c.column key: "count", abbr: "n", label: "Anzahl", numeric: true, width: "5rem",
      sort: "wsjrdp_direct_debit_payment_infos.number_of_transactions", sort_first: "desc", default: true
    c.column key: "sum", abbr: "sum", label: "Betrag", numeric: true, width: "8rem", tabular_nums: true,
      sort: "wsjrdp_direct_debit_payment_infos.control_sum_cents", sort_first: "desc", default: true
    c.column key: "returns", abbr: "ret", label: "Retouren", numeric: true, width: "8.5rem", tabular_nums: true,
      sort: "COALESCE(returns.return_sum_cents, 0)", default: true
    c.column key: "bank", abbr: "bk", label: "Bankbuchung", width: "7.5rem", narrow: false,
      header_tooltip: "Die Gutschrift der Bank zu diesem Sammler",
      sort: "credits.credit_date", sort_first: "desc", default: true
    c.column key: "creditor_id", abbr: "ci", label: "Gläubiger-ID", width: "11rem", narrow: false,
      sort: "wsjrdp_direct_debit_payment_infos.creditor_id"
  end
end
