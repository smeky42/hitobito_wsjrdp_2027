# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Columns of the Aufträge list (/fin/payments/orders): one order (a SEPA file)
# per row over Fin::PaymentQueries.orders, so every column sorts by SQL; an
# order of several payment infos (Sammler) shows its date, sequence type,
# count, amount, returns and bank credit per Sammler as small lines under the
# order's own (Fin::PaymentsHelper#payment_order_stack). The
# list names nobody -- its figures are the order's own and the sums of its
# debits and returns -- so whoever sees the accounts sees it.
#
# Where the table would scroll sideways ID, Konto, Erstellt, Sequenz, Status
# and Bankbuchung give way (narrow: false); the order's page shows them.
module Fin::PaymentOrdersColumns
  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "pocol") do |c|
    c.column key: "id", abbr: "id", label: "ID", numeric: true, width: "3.5rem", narrow: false,
      sort: "wsjrdp_payment_initiations.id", sort_first: "desc", default: true
    c.column key: "kind", abbr: "kd", label: "Typ", width: "7.5rem",
      sort: WsjrdpPaymentInitiation.kind_sql, default: true
    c.column key: "account", abbr: "acc", label: "Konto", width: "5rem", target_width: "11rem", grow: 1,
      narrow: false, sort: "LOWER(COALESCE(accounts.short_name, accounts.account_identification))"
    c.column key: "created_at", abbr: "ca", label: "Erstellt", width: "8.5rem", tabular_nums: true, narrow: false,
      sort: "wsjrdp_payment_initiations.created_at", sort_first: "desc"
    c.column key: "execution_date", abbr: "ex", label: "Ausführung", width: "7.75rem", tabular_nums: true,
      header_tooltip: "Das (früheste) Einzugs- bzw. Ausführungsdatum des Auftrags",
      sort: "infos.first_date", sort_first: "desc", default: true
    c.column key: "sequence", abbr: "seq", label: "Sequenz", width: "5.5rem", narrow: false,
      header_tooltip: "Lastschrift-Sequenztypen: FRST erste, RCUR Folge-, OOFF einmalige, FNAL letzte Lastschrift",
      sort: "infos.sequence_types", default: true
    c.column key: "count", abbr: "n", label: "Anzahl", numeric: true, width: "5rem",
      sort: "wsjrdp_payment_initiations.number_of_transactions", sort_first: "desc", default: true
    c.column key: "sum", abbr: "sum", label: "Betrag", numeric: true, width: "8rem", tabular_nums: true,
      sort: "wsjrdp_payment_initiations.control_sum_cents", sort_first: "desc", default: true
    c.column key: "returns", abbr: "ret", label: "Retouren", numeric: true, width: "8.5rem", tabular_nums: true,
      header_tooltip: "Anzahl und Summe der Rücklastschriften zu den Einzügen des Auftrags",
      sort: "COALESCE(returns.return_sum_cents, 0)", sort_first: "asc", default: true
    c.column key: "status", abbr: "st", label: "Status", width: "7.5rem", narrow: false,
      sort: "wsjrdp_payment_initiations.status", default: true
    c.column key: "bank", abbr: "bk", label: "Bankbuchung", width: "7.75rem", narrow: false,
      header_tooltip: "Die Gutschrift(en) der Bank zu den Sammlern des Auftrags laut Kontoauszug",
      sort: "credits.credit_date", sort_first: "desc", default: true
    c.column key: "skipped", abbr: "sk", label: "Übersprungen", numeric: true, width: "6.5rem",
      sort: "notices.skipped_count", sort_first: "desc"
    c.column key: "message_identification", abbr: "mid", label: "Nachrichten-ID", width: "14rem",
      sort: "wsjrdp_payment_initiations.message_identification"
    c.column key: "sepa_schema", abbr: "sch", label: "Schema", width: "9rem",
      sort: "wsjrdp_payment_initiations.sepa_schema"
  end
end
