# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Synchronisation" (doc/fin/sync.md): the overview and the two sources,
# Moss API and Moss CSV. Only Admin and the manage tier may use it, because
# it writes data from Moss into the database.
class Fin::SyncController < Fin::FinController
  include Fin::SyncTables

  # A run's detail in a row of the runs table shows its parts closed.
  sync_tables

  # How many of the newest runs the tables show.
  RUNS_SHOWN = 200

  RUNS_POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: Fin::SyncRunsColumns::COLUMNS.codec,
    cols: {default: Fin::SyncRunsColumns::COLUMNS.default_keys},
    per_page: {default: 25}

  helper_method :sync_runs

  before_action { authorize!(:configure_finance, Group) }

  def index
  end

  def moss_api
  end

  def moss_csv
  end

  # Deletes the files of old runs (Wsjrdp::Sync::Purge).
  def purge
    redirect_to fin_sync_path, notice: t("fin.sync.overview.purged", count: Wsjrdp::Sync::Purge.call)
  end

  private

  # The newest runs, of one source or all, newest first until a header sorts.
  def sync_runs(source = nil)
    runs = WsjrdpSyncRun.newest_first.includes(:started_by, :confirmed_by, :warnings_confirmed_by, :parts).limit(RUNS_SHOWN)
    runs = runs.where(source: source) if source
    Wsjrdp::ExpandableTableRows.new(wsjrdp_expandable_table_state(RUNS_POLICY), runs.to_a,
      sort: Fin::SyncRunsColumns::COLUMNS.sort_expressions, tiebreaker: ->(run) { -run.id })
  end
end
