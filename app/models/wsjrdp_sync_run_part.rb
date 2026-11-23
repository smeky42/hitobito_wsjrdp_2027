# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# One part of a Synchronisation run (doc/fin/sync.md): its plan as shown,
# the digest writing checks, and its files.
class WsjrdpSyncRunPart < ActiveRecord::Base
  PLANNED = "planned"
  APPLIED = "applied"
  UNCHANGED = "unchanged"
  STALE = "stale"
  FAILED = "failed"
  SKIPPED = "skipped"
  STATES = [PLANNED, APPLIED, UNCHANGED, STALE, FAILED, SKIPPED].freeze

  belongs_to :run, class_name: "WsjrdpSyncRun", inverse_of: :parts

  validates :part_key, :fetch_started_at, presence: true
  validates :status, inclusion: {in: STATES}

  # When a part was last started, and last written, in UTC.
  def self.last_started_at(part_key) = where(part_key: part_key).maximum(:fetch_started_at)

  def self.last_applied_at(part_key) = where(part_key: part_key).maximum(:applied_at)

  def writable? = [PLANNED, STALE].include?(status)

  def modified_rows = Wsjrdp::Sync::Stats.of(stats)

  def duration_ms = timings.sum { |entry| entry["duration_ms"].to_i }

  # The plan, parsed once until it is set or reloaded.
  def plan_object = @plan_object ||= Wsjrdp::Sync::Plan.from_h(plan)

  def plan=(value)
    @plan_object = nil
    super
  end

  def reload(...)
    @plan_object = nil
    super
  end

  def warnings? = plan_object.warnings?

  def part_class = Wsjrdp::Sync.part(part_key)
end
