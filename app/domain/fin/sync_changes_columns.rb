# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
# Columns of a part's change table in a sync run's detail (fin/sync_runs/_part_detail):
# one Fin::SyncChangesColumns::Row per change, array-backed.
module Fin::SyncChangesColumns
  # A change, the notices about its record and the changes that belong to
  # it (a Moss user's person). A change whose record is unchanged but
  # whose ref is set stands for that record (the person of an unchanged
  # Moss user).
  Row = Data.define(:change, :notices, :position, :related) do
    def initialize(change:, notices:, position:, related: []) = super

    def changes = [change, *related]
  end

  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "sccol") do |c|
    c.column key: "action", abbr: "ac", label: "Aktion", width: "6rem",
      sort: ->(row) { Wsjrdp::Sync::Plan::ACTIONS.index(row.change.action) }, default: true
    c.column key: "record", abbr: "rc", label: "Datensatz", width: "10rem", target_width: "16rem", truncate: true,
      sort: ->(row) { row.change.label.to_s.downcase }, default: true
    c.column key: "values", abbr: "vl", label: "Ziele", width: "10rem", grow: 4, default: true
    c.column key: "hints", abbr: "hn", label: "Hinweise", width: "12rem", target_width: "18rem",
      sort: ->(row) { -row.notices.size }, default: true
  end

  # One row per record: a change with a ref to another change of the plan
  # goes into that change's row.
  def self.rows(plan)
    keys = plan.changes.to_set { |change| change.key.to_s.downcase }
    attached, own = plan.changes.partition { |change| change.ref && keys.include?(change.ref.to_s.downcase) }
    by_ref = attached.group_by { |change| change.ref.to_s.downcase }
    own.each_with_index.map do |change, position|
      key = change.key.to_s.downcase
      notices = plan.notices_by_key[key].presence || (change.ref ? plan.notices_by_key[change.ref.to_s.downcase] : [])
      Row.new(change: change, notices: notices, position: position, related: by_ref[key] || [])
    end
  end
end
