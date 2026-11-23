# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
# The tables of a sync run's detail (fin/sync_runs/_detail): its parts, each
# part's changes, its phases. Shared by the run's page and the runs table,
# whose rows show the same detail. A host calls sync_tables with its own
# defaults: the run's page opens every part and pages changes by 50, a row
# opens none and pages by 25.
#
# Each part has its own changes table (prefix "sc" plus a letter per part of
# the registry), so paging one part leaves the others where they are.
module Fin::SyncTables
  extend ActiveSupport::Concern

  included do
    include Wsjrdp::TableStateful

    helper_method :part_rows, :change_rows, :timing_rows
  end

  class_methods do
    # open_parts: ->{ keys } of the parts shown open, evaluated per request.
    # changes_per_page: the default page size of a part's changes.
    def sync_tables(open_parts: nil, changes_per_page: 25)
      every_row = {default: :all}
      const_set(:PARTS_POLICY, wsjrdp_expandable_table_policy(prefix: "sp",
        columns: Fin::SyncPartsColumns::COLUMNS.codec,
        cols: {default: Fin::SyncPartsColumns::COLUMNS.default_keys},
        per_page: every_row, **(open_parts ? {open: {default: open_parts}} : {})))
      changes = ->(prefix) {
        wsjrdp_expandable_table_policy(prefix: prefix,
          columns: Fin::SyncChangesColumns::COLUMNS.codec,
          cols: {default: Fin::SyncChangesColumns::COLUMNS.default_keys},
          per_page: {default: changes_per_page})
      }
      const_set(:CHANGES_POLICIES, Wsjrdp::Sync.parts.each_with_index.to_h { |part, index|
        [part.key, changes.call("sc#{("a".."z").to_a.fetch(index)}")]
      }.freeze)
      # A part no longer in the registry.
      const_set(:CHANGES_POLICY, changes.call("sc"))
      const_set(:TIMINGS_POLICY, wsjrdp_expandable_table_policy(prefix: "st",
        columns: Fin::SyncTimingsColumns::COLUMNS.codec,
        cols: {default: Fin::SyncTimingsColumns::COLUMNS.default_keys},
        per_page: every_row))
    end
  end

  private

  def part_rows(run)
    Wsjrdp::ExpandableTableRows.new(wsjrdp_expandable_table_state(self.class::PARTS_POLICY), run.parts.to_a,
      sort: Fin::SyncPartsColumns::COLUMNS.sort_expressions, tiebreaker: ->(part) { part.position })
  end

  def change_rows(part)
    policy = self.class::CHANGES_POLICIES.fetch(part.part_key, self.class::CHANGES_POLICY)
    Wsjrdp::ExpandableTableRows.new(wsjrdp_expandable_table_state(policy),
      Fin::SyncChangesColumns.rows(part.plan_object), sort: Fin::SyncChangesColumns::COLUMNS.sort_expressions,
      tiebreaker: ->(row) { row.position })
  end

  def timing_rows(run)
    Wsjrdp::ExpandableTableRows.new(wsjrdp_expandable_table_state(self.class::TIMINGS_POLICY),
      Fin::SyncTimingsColumns.rows(run), sort: Fin::SyncTimingsColumns::COLUMNS.sort_expressions,
      tiebreaker: ->(row) { row.position })
  end
end
