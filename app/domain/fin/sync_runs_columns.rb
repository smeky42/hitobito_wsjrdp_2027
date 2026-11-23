# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
# Columns of the runs tables of the Synchronisation (fin/sync/_runs): one
# WsjrdpSyncRun per row, array-backed. "Geschrieben" sums up the rows
# written (Wsjrdp::Sync::Stats); the four counts are there to choose.
module Fin::SyncRunsColumns
  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "srcol") do |c|
    c.column key: "id", abbr: "id", label: "ID", numeric: true, width: "3.5rem",
      sort: ->(run) { run.id }, sort_first: "desc", default: true
    c.column key: "started_at", abbr: "st", label: "Gestartet", width: "9rem", target_width: "11rem", grow: 1,
      tabular_nums: true, sort: ->(run) { run.started_at }, sort_first: "desc", default: true
    c.column key: "source", abbr: "so", label: "Quelle", width: "6rem", grow: 1, narrow: false,
      sort: ->(run) { run.source }, default: true
    c.column key: "parts", abbr: "pa", label: "Teile", width: "8rem", target_width: "16rem", grow: 3, truncate: true,
      narrow: false, default: true
    c.column key: "status", abbr: "sa", label: "Status", width: "7.5rem", grow: 1,
      sort: ->(run) { run.status }, default: true
    c.column key: "duration", abbr: "du", label: "Dauer", numeric: true, width: "4.5rem",
      sort: ->(run) { run.duration_ms }, default: true
    c.column key: "written", abbr: "wr", label: "Geschrieben", width: "8rem", grow: 2, truncate: true, narrow: false,
      sort: ->(run) { run.modified_rows.total }, default: true
    c.column key: "started_by", abbr: "by", label: "Gestartet von", width: "8rem", truncate: true,
      sort: ->(run) { run.started_by.to_s.downcase }
    {"inserted" => ["in", "Eingefügt"], "updated" => ["up", "Geändert"], "deleted" => ["de", "Gelöscht"],
     "soft_deleted" => ["sd", "Als entfernt markiert"]}.each do |key, (abbr, label)|
      c.column key: key, abbr: abbr, label: label, numeric: true, width: "5.5rem",
        sort: ->(run) { run.modified_rows[key] }
    end
  end
end
