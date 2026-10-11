# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Column definitions of the Zahlungscodes list (Verwaltung,
# /fin/admin/payment_references): one WsjrdpPaymentReference per row. The rows
# are a relation (Fin::PaymentReferencesController#payment_references), so
# every column sorts by an SQL expression.
#
# The number of payment notices using a code is a correlated subquery
# (NOTICE_COUNT_SQL): the list selects it as `notice_count` for the cell, sorts
# by the same expression and Fin::PaymentReferencesFilterSchema filters on it,
# so the three cannot count differently. Every notice counts, whatever its
# status -- a reference stays assigned whatever becomes of its notices.
module Fin::PaymentReferencesColumns
  NOTICE_COUNT_SQL = "(SELECT COUNT(*) FROM wsjrdp_payment_notices notices " \
    "WHERE notices.payment_reference_id = wsjrdp_payment_references.id)"

  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "prcol") do |c|
    # The printed form, in groups of four; sorted by the electronic one.
    c.column key: "payment_code", abbr: "pc", label: "Code", width: "12.5rem",
      sort: "wsjrdp_payment_references.payment_code", default: true
    c.column key: "status", abbr: "st", label: "Status", width: "6.5rem",
      sort: "wsjrdp_payment_references.status", default: true
    c.column key: "origin", abbr: "or", label: "Herkunft", width: "8.5rem",
      sort: "wsjrdp_payment_references.origin", default: true
    c.column key: "created_at", abbr: "ca", label: "Erzeugt", width: "8.5rem",
      sort: "wsjrdp_payment_references.created_at", sort_first: "desc", default: true
    c.column key: "assigned_at", abbr: "aa", label: "Vergeben", width: "8.5rem",
      sort: "wsjrdp_payment_references.assigned_at", sort_first: "desc", default: true
    c.column key: "notice_count", abbr: "nc", label: "Zahlungsankündigungen", header_label: "Ankündigungen",
      header_tooltip: "Zahlungsankündigungen mit diesem Code", numeric: true, width: "8rem",
      sort: NOTICE_COUNT_SQL, sort_first: "desc", default: true
    # In the columns menu only.
    c.column key: "comment", abbr: "cm", label: "Kommentar", width: "14rem",
      sort: "LOWER(wsjrdp_payment_references.comment)"
  end
end
