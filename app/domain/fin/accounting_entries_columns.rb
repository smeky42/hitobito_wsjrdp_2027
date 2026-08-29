# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# THE columns of the unmatched-Beitragsbuchungen table on the reconciliation page
# (fin/reconciliation/participant_fees, prefix "ae"), described once
# (doc/wsjrdp/expandable_table.md).
#
# Person and Quelle are display-only: both are derived from the entry's subject
# resp. its source association, so neither has an ORDER BY to offer. The table
# declares no sort DEFAULT -- with an empty sort list its natural order is
# "match proposals first" (Fin::ReconciliationController#order_proposals_first).
module Fin::AccountingEntriesColumns
  COLUMNS = Wsjrdp::ExpandableTableColumns.define do |c|
    c.column key: "date", abbr: "date", label: "Datum", width: "6.5rem", default: true,
      sort: "COALESCE(accounting_entries.value_date, accounting_entries.booking_date)"
    c.column key: "amount", abbr: "amount", label: "Betrag", numeric: true, width: "7rem",
      sort: "accounting_entries.amount_cents", default: true
    c.column key: "description", abbr: "descr", label: "Beschreibung",
      sort: "accounting_entries.description", default: true
    c.column key: "person", abbr: "person", label: "Person", width: "14rem"
    c.column key: "source", abbr: "source", label: "Quelle", width: "7rem"
  end

  def self.codec = COLUMNS.codec

  def self.default_keys = COLUMNS.default_keys

  def self.sort_expressions = COLUMNS.sort_expressions
end
