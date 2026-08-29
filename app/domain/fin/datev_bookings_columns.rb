# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# THE columns of a DATEV bookings table -- the Buchungen list, the reconciliation
# page's bookings table and the condensed table embedded in a Buchhaltung item's
# detail all describe their columns here, once
# (doc/wsjrdp/expandable_table.md).
#
# Note: "Konto" (account_number) always renders number + name, so there is no
# separate "Kontobezeichnung" column. account_kind, offsetting_account_kind,
# KOST1/KOST2, the Primanota number and the raw Buchungstext are purely internal
# and are shown only in the detail view, not as columns.
#
# `sort:` is the SQL expression the ORDER BY uses (Wsjrdp::ExpandableTableRows
# takes the map as its allow-list, so only these fixed, safe expressions can ever
# reach SQL). primanota_period sorts on datev_booking_batches, which is why every
# host of this table hands the rows object a batch-joined relation.
module Fin::DatevBookingsColumns
  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "bkcol") do |c|
    c.column key: "booking_date", abbr: "bdt", label: "Datum", width: "7rem",
      sort: "booking_date", default: true
    c.column key: "service_date", abbr: "sdt", label: "Leistungsdatum", width: "7rem",
      sort: "service_date"
    c.column key: "signed_base_amount", abbr: "amt", label: "Betrag", numeric: true,
      width: "8rem", sort: "signed_base_amount", default: true
    c.column key: "posting_text", abbr: "posting_text", label: "Beschreibung",
      width: "16rem", sort: "posting_text", default: true
    # The condensed (in-detail) table abbreviates the headers of the code
    # columns, since only the bare code is shown there (no account /
    # cost-center / supplier name).
    c.column key: "cost_center_number", abbr: "cc", label: "Kostenstelle",
      condensed_label: "KSt", width: "9rem", sort: "cost_center_number", default: true
    c.column key: "secondary_cost_center_number", abbr: "cc2", label: "Sekundäre Kostenstelle",
      condensed_label: "KSt 2", width: "11rem", sort: "secondary_cost_center_number"
    c.column key: "account_number", abbr: "acc", label: "Konto", condensed_label: "Kto",
      width: "13rem", sort: "account_number", default: true
    c.column key: "offsetting_account_number", abbr: "oacc", label: "Gegenkonto",
      condensed_label: "Gkto", width: "13rem", sort: "offsetting_account_number", default: true
    c.column key: "document_field_1", abbr: "df1", label: "Belegfeld 1", width: "9rem",
      sort: "document_field_1"
    c.column key: "document_field_2", abbr: "df2", label: "Belegfeld 2", width: "9rem",
      sort: "document_field_2"
    c.column key: "primanota_period", abbr: "priper", label: "Primanota Periode",
      width: "8.5rem", sort: "date_trunc('month', datev_booking_batches.period_to)"
    c.column key: "sphere_number", abbr: "sphere", label: "Sphäre", width: "5rem",
      sort: "sphere_number"
  end

  def self.codec = COLUMNS.codec

  def self.default_keys = COLUMNS.default_keys

  def self.sort_expressions = COLUMNS.sort_expressions

  # What a page of this table preloads: the batch (the Primanota-Periode column
  # reads it) and the linked Beitragsbuchung, which no column shows but the
  # detail's "Verknüpfungen" block does (fin/bookings/_booking_detail) -- and
  # the widget renders a direct detail for every row of the page, collapsed or
  # not, so it is one query for the page instead of one per row.
  #
  # The two Moss back-links feed the detail's "In Moss" header link: this
  # booking is either the clearing booking of a transaction or the expense
  # booking of one of its splits, and the split's transaction carries the URL.
  PRELOADS = [:batch, :accounting_entry, :moss_transaction_as_clearing,
    {moss_booking_as_expense: :moss_transaction}].freeze
end
