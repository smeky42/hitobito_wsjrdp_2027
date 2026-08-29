# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Column definitions for the Buchungsstapel (booking batches) index page.
#
# The base relation joins bookings and groups by batch id to provide the
# booking_count aggregate. The `period` column is derived -- the cell formats
# `period_to` as an ISO 8601 month (YYYY-MM), but the sort is on the raw
# `period_to` date so chronological order is correct.
module Fin::BookingBatchesColumns
  BATCHES = Wsjrdp::ExpandableTableColumns.define do |c|
    c.column key: "label", abbr: "bez", label: "Bezeichnung", width: "18rem",
      sort: "LOWER(label)", default: true
    c.column key: "period", abbr: "per", label: "Periode", width: "10rem",
      sort: "period_to", default: true
    c.column key: "primanota_number", abbr: "pn", label: "Primanota", width: "7rem",
      sort: "primanota_number", default: true
    c.column key: "period_from", abbr: "pf", label: "Periode von", width: "9rem",
      sort: "period_from", default: true
    c.column key: "period_to", abbr: "pt", label: "Periode bis", width: "9rem",
      sort: "period_to", default: true
    c.column key: "booking_count", abbr: "bc", label: "Buchungen", numeric: true,
      width: "7rem", sort: "booking_count", default: true
    c.column key: "is_finalized", abbr: "fin", label: "Festgeschrieben", width: "9rem",
      sort: "is_finalized", default: false
  end
end
