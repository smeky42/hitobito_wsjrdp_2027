# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The runs of the Synchronisation and their parts (doc/fin/sync.md). The raw
# data lies in files, never here.
#
# - timings: the phases, each {phase, started_at, finished_at, duration_ms,
#   status (succeeded, failed, stale), error_message (when failed)}.
# - stats: figures of the run or part; for now {modified_rows: {inserted,
#   updated, deleted, soft_deleted}}, the rows of content tables written.
class CreateWsjrdpSyncRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :wsjrdp_sync_runs do |t|
      t.string :source, null: false # moss_api, later moss_csv, datev, ...
      t.string :credential_source, null: true, comment: "DB, ENV or YAML"
      t.string :credential_kind, null: true
      t.string :account_key, null: true
      # NULL for a credential from ENV or YAML
      t.references :credential, null: true, foreign_key: {to_table: :wsjrdp_credentials, on_delete: :nullify}
      t.string :selected_parts, array: true, null: false, default: [] # part keys, dependencies added, in order
      t.string :status, null: false,
        comment: "planned, applying, stopped, applied, partly_applied, unchanged, failed, cancelled"
      t.datetime :started_at, null: false # also the start of the run's file names
      t.references :started_by, null: true, foreign_key: {to_table: :people, on_delete: :nullify}
      t.datetime :confirmed_at, null: true
      t.references :confirmed_by, null: true, foreign_key: {to_table: :people, on_delete: :nullify}
      t.datetime :warnings_confirmed_at, null: true
      t.references :warnings_confirmed_by, null: true, foreign_key: {to_table: :people, on_delete: :nullify}
      t.datetime :finished_at, null: true
      t.text :error_message, null: true # only when the run failed or stopped
      t.jsonb :timings, null: false, default: []
      t.jsonb :stats, null: false, default: {}
      t.jsonb :additional_info, null: false, default: {}
      t.timestamps
      t.index :started_at
    end

    create_table :wsjrdp_sync_run_parts do |t|
      t.references :run, null: false, foreign_key: {to_table: :wsjrdp_sync_runs, on_delete: :cascade}
      t.string :part_key, null: false # e.g. moss_api.organisation_structure.users; never changes
      t.integer :position, null: false
      t.string :status, null: false, comment: "planned, applied, unchanged, stale, failed, skipped"
      t.datetime :fetch_started_at, null: false
      t.datetime :applied_at, null: true
      t.jsonb :plan, null: false, default: {} # the changes and notices shown
      t.string :plan_digest, null: true # SHA-256 of the plan; writing checks it
      t.jsonb :counts, null: false, default: {} # changes per action
      t.jsonb :files, null: false, default: [] # name, file, size, sha256
      t.datetime :files_purged_at, null: true
      t.text :error_message, null: true # only when the part failed
      t.jsonb :timings, null: false, default: []
      t.jsonb :stats, null: false, default: {}
      t.jsonb :additional_info, null: false, default: {}
      t.timestamps
      t.index [:run_id, :position], unique: true
      t.index [:part_key, :fetch_started_at]
      t.index [:part_key, :applied_at]
    end
  end
end
