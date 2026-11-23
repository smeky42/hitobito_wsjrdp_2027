# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
# Columns of the parts table in a sync run's detail (fin/sync_runs/_detail):
# one WsjrdpSyncRunPart per row, array-backed, in the run's order.
module Fin::SyncPartsColumns
  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "spcol") do |c|
    c.column key: "part", abbr: "pa", label: "Teil", width: "8rem", target_width: "11rem", grow: 2, default: true
    c.column key: "status", abbr: "sa", label: "Status", width: "7rem", grow: 1,
      sort: ->(part) { part.status }, default: true
    c.column key: "changes", abbr: "ch", label: "Änderungen", width: "9rem", grow: 3, truncate: true, narrow: false,
      sort: ->(part) { part.counts.values.sum }, default: true
    c.column key: "written", abbr: "wr", label: "Geschrieben", width: "8rem", grow: 3, truncate: true, narrow: false,
      sort: ->(part) { part.modified_rows.total }, default: true
    c.column key: "duration_ms", abbr: "ms", label: "Dauer (ms)", header_label: "Dauer", numeric: true,
      width: "6rem", sort: ->(part) { part.duration_ms }, default: true
    c.column key: "duration", abbr: "du", label: "Dauer (lesbar)", header_label: "", width: "4rem", narrow: false, default: true
    c.column key: "notices", abbr: "no", label: "Hinweise", width: "5rem", grow: 1,
      sort: ->(part) { part.plan_object.warnings.size }, default: true
  end
end
