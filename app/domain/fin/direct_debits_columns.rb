# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Columns of the Einzüge tables -- the tab (/fin/payments/debits) and the
# section of an order's page: one debit (pre-notification) per row over
# Fin::PaymentQueries.debits, with its collection entry and its returns. The
# tab adds Auftrag, the order's page leaves it out (it is that order).
#
# Where the table would scroll sideways Bezahlungs-Rolle, Sequenz, Status and
# Buchung give way (narrow: false); the row's detail shows them.
module Fin::DirectDebitsColumns
  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "ddcol") do |c|
    c.column key: "person", abbr: "p", label: "Person", width: "9rem", target_width: "16rem", grow: 1,
      sort: "LOWER(people.last_name || ' ' || people.first_name)", default: true
    c.column key: "role", abbr: "rl", label: "Bezahlungs-Rolle", width: "7.5rem", narrow: false,
      sort: "wsjrdp_direct_debit_pre_notifications.payment_role"
    c.column key: "order", abbr: "o", label: "Auftrag", numeric: true, width: "5rem", narrow: false,
      sort: "wsjrdp_direct_debit_pre_notifications.payment_initiation_id", sort_first: "desc", default: true
    c.column key: "collection_date", abbr: "cd", label: "Einzug", width: "6.5rem", tabular_nums: true,
      sort: "wsjrdp_direct_debit_pre_notifications.collection_date", sort_first: "desc", default: true
    c.column key: "sequence", abbr: "seq", label: "Sequenz", width: "5rem", narrow: false,
      sort: "wsjrdp_direct_debit_pre_notifications.debit_sequence_type", default: true
    c.column key: "amount", abbr: "a", label: "Betrag", numeric: true, width: "7rem", tabular_nums: true,
      sort: "wsjrdp_direct_debit_pre_notifications.amount_cents", sort_first: "desc", default: true
    c.column key: "pre_notified_amount", abbr: "pa", label: "Angekündigt", numeric: true, width: "7rem",
      tabular_nums: true, header_tooltip: "Der in der Vorabankündigung genannte Betrag",
      sort: "wsjrdp_direct_debit_pre_notifications.pre_notified_amount_cents", sort_first: "desc"
    c.column key: "status", abbr: "st", label: "Status", width: "7rem", narrow: false,
      sort: "wsjrdp_direct_debit_pre_notifications.payment_status", default: true
    c.column key: "entry", abbr: "e", label: "Buchung", width: "5rem", header_align: "center", narrow: false,
      header_tooltip: "Die Beitragsbuchung des Einzugs",
      sort: "(entry.id IS NOT NULL)", default: true
    c.column key: "return", abbr: "r", label: "Rücklastschrift", width: "9rem", target_width: "11rem", grow: 1,
      sort: "returns.return_date", sort_first: "desc", default: true
    c.column key: "dbtr_name", abbr: "dn", label: "Kontoinhaber", width: "10rem",
      sort: "LOWER(wsjrdp_direct_debit_pre_notifications.dbtr_name)"
    c.column key: "dbtr_iban", abbr: "di", label: "IBAN", width: "13rem",
      sort: "wsjrdp_direct_debit_pre_notifications.dbtr_iban"
    c.column key: "mandate_id", abbr: "mi", label: "Mandat", width: "9rem",
      sort: "wsjrdp_direct_debit_pre_notifications.mandate_id"
    c.column key: "description", abbr: "ds", label: "Verwendungszweck", width: "14rem", target_width: "32rem", grow: 2,
      sort: "LOWER(wsjrdp_direct_debit_pre_notifications.description)"
    c.column key: "endtoend_id", abbr: "ee", label: "End-to-End-ID", width: "13rem",
      sort: "wsjrdp_direct_debit_pre_notifications.endtoend_id"
    c.column key: "email_to", abbr: "em", label: "E-Mail an", width: "13rem",
      sort: "LOWER(wsjrdp_direct_debit_pre_notifications.email_to)"
    c.column key: "id", abbr: "id", label: "ID", numeric: true, width: "4.5rem",
      sort: "wsjrdp_direct_debit_pre_notifications.id", sort_first: "desc"
  end
end
