# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# THE columns of the three Buchhaltung summary tables (Sachkonten, Kostenstellen,
# Kreditoren), described once each (doc/wsjrdp/expandable_table.md).
#
# All three lists are RELATION-backed -- WsjrdpLedgerAccount.with_booking_summary,
# WsjrdpCostCenter.with_booking_summary and
# WsjrdpPersonalAccount.with_booking_summary put the booking totals into the
# relation as real columns, which is what lets the pages filter in SQL. Every
# `sort:` below is therefore an SQL expression over that relation's own columns:
#
#   - a `number` is ordered as the STRING it is: account and cost-center numbers
#     may contain letters, and a numeric cast would collapse all of those into
#     one value;
#   - the names are lower-cased, so the alphabetical order does not depend on
#     capitalisation;
#   - the Moss status goes through the same COALESCE that makes NULL count as
#     deactivated.
module Fin::BookkeepingSummaryColumns
  # NULL counts as deactivated -- the one expression the pages showing a Moss
  # status sort by, filter on and render their "Moss Status" cell from. All
  # models spell the two states identically.
  MOSS_STATUS_SQL = "COALESCE(moss_status, '#{WsjrdpCostCenter::STATUS_DEACTIVATED}')"

  # Sachkonten: relation-backed. Its keys are the attribute keys of
  # Fin::LedgerAccountsFilterSchema wherever that schema has one, so a filter
  # condition and a sorted header name the same thing. "Kontoart" sorts by the
  # DATEV short code the column stores, not by its German label.
  LEDGER_ACCOUNTS = Wsjrdp::ExpandableTableColumns.define do |c|
    c.column key: "number", abbr: "nr", label: "Konto", width: "8rem",
      sort: "number", default: true
    c.column key: "name", abbr: "bez", label: "Bezeichnung", width: "18rem",
      sort: "LOWER(name)", default: true
    c.column key: "short_name", abbr: "kbz", label: "Kurzbezeichnung", width: "9rem",
      sort: "LOWER(short_name)", default: true
    c.column key: "account_kind", abbr: "art", label: "Kontoart", width: "9rem",
      sort: "account_kind", default: true
    c.column key: "moss_status", abbr: "ms", label: "Moss Status", width: "8rem",
      sort: MOSS_STATUS_SQL, default: true
    c.column key: "booking_sum", abbr: "sum", label: "Summe", numeric: true,
      width: "10rem", sort: "booking_sum", default: true
    c.column key: "booking_count", abbr: "bc", label: "Buchungen", numeric: true,
      width: "7rem", sort: "booking_count", default: true
  end

  # Kostenstellen: relation-backed. Its keys are the attribute keys of
  # Fin::CostCentersFilterSchema wherever that schema has one, so a filter
  # condition and a sorted header name the same thing, and every column sorts
  # (the Moss status included).
  COST_CENTERS = Wsjrdp::ExpandableTableColumns.define do |c|
    c.column key: "number", abbr: "nr", label: "Kostenstelle", width: "9rem",
      sort: "number", default: true
    c.column key: "name", abbr: "bez", label: "Bezeichnung", width: "18rem",
      sort: "LOWER(name)", default: true
    c.column key: "short_name", abbr: "kbz", label: "Kurzbezeichnung", width: "9rem",
      sort: "LOWER(short_name)", default: true
    c.column key: "moss_status", abbr: "ms", label: "Moss Status", width: "8rem",
      sort: MOSS_STATUS_SQL, default: true
    c.column key: "booking_sum", abbr: "sum", label: "Summe", numeric: true,
      width: "10rem", sort: "booking_sum", default: true
    c.column key: "booking_count", abbr: "bc", label: "Buchungen", numeric: true,
      width: "7rem", sort: "booking_count", default: true
  end

  # Kreditoren: relation-backed as well. Its keys are the attribute keys of
  # Fin::PersonalAccountsFilterSchema.
  PERSONAL_ACCOUNTS = Wsjrdp::ExpandableTableColumns.define do |c|
    c.column key: "number", abbr: "nr", label: "Kreditor", width: "9rem",
      sort: "number", default: true
    c.column key: "name", abbr: "bez", label: "Name", width: "18rem",
      sort: "LOWER(name)", default: true
    c.column key: "moss_status", abbr: "ms", label: "Moss Status", width: "8rem",
      sort: MOSS_STATUS_SQL, default: true
    c.column key: "booking_balance", abbr: "bb", label: "Saldo", numeric: true,
      width: "10rem", sort: "booking_balance", default: true
    c.column key: "booking_count", abbr: "bc", label: "Buchungen", numeric: true,
      width: "7rem", sort: "booking_count", default: true
  end
end
