# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
# Columns of the „Ablauf“ table on a sync run's page (fin/sync_runs/_timings):
# one phase of the run or of a part per row, array-backed. Start and end
# show the time of day; the date only when it is not the run's. The duration is
# two columns: the milliseconds, right-aligned, then the same in seconds or
# minutes, muted.
module Fin::SyncTimingsColumns
  # part: nil for a phase of the run itself.
  Row = Data.define(:part, :phase, :started_at, :finished_at, :duration_ms, :status, :error_message, :position)

  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "stcol") do |c|
    c.column key: "phase", abbr: "ph", label: "Phase", width: "7rem", target_width: "10rem", grow: 3, default: true
    c.column key: "step", abbr: "sp", label: "Schritt", width: "6.5rem", grow: 2, default: true
    c.column key: "started_at", abbr: "st", label: "Start", width: "5rem", grow: 1, tabular_nums: true,
      sort: ->(row) { row.started_at }, default: true
    c.column key: "finished_at", abbr: "fi", label: "Ende", width: "5rem", grow: 1, tabular_nums: true, narrow: false,
      sort: ->(row) { row.finished_at }, default: true
    c.column key: "duration_ms", abbr: "ms", label: "Dauer (ms)", header_label: "Dauer", numeric: true,
      width: "6rem", sort: ->(row) { row.duration_ms.to_i }, default: true
    c.column key: "duration", abbr: "du", label: "Dauer (lesbar)", header_label: "", width: "4rem", narrow: false,
      default: true
  end

  # The run's phases and its parts', in the order they started.
  def self.rows(run)
    rows = run.timings.map { |entry| row(entry, nil) } +
      run.parts.flat_map { |part| part.timings.map { |entry| row(entry, part.part_key) } }
    rows.sort_by { |row| [row.started_at || Time.zone.at(0), row.part ? 1 : 0] }
      .each_with_index.map { |row, position| row.with(position: position) }
  end

  def self.row(entry, part)
    Row.new(part: part, phase: entry["phase"], status: entry["status"], error_message: entry["error_message"],
      duration_ms: entry["duration_ms"],
      started_at: Wsjrdp::InstantInput.parse(entry["started_at"]),
      finished_at: Wsjrdp::InstantInput.parse(entry["finished_at"]), position: 0)
  end
end
