# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# One run of the Synchronisation (doc/fin/sync.md): the parts chosen, who
# started and confirmed it, and how far it got.
class WsjrdpSyncRun < ActiveRecord::Base
  PLANNED = "planned"
  APPLYING = "applying"
  STOPPED = "stopped"
  APPLIED = "applied"
  PARTLY_APPLIED = "partly_applied"
  # Nothing to change: ended right after the preview.
  UNCHANGED = "unchanged"
  FAILED = "failed"
  CANCELLED = "cancelled"
  STATES = [PLANNED, APPLYING, STOPPED, APPLIED, PARTLY_APPLIED, UNCHANGED, FAILED, CANCELLED].freeze
  # A run in these states may still write.
  OPEN = [PLANNED, STOPPED].freeze

  belongs_to :credential, class_name: "WsjrdpCredential", optional: true
  belongs_to :started_by, class_name: "Person", optional: true
  belongs_to :confirmed_by, class_name: "Person", optional: true
  belongs_to :warnings_confirmed_by, class_name: "Person", optional: true
  has_many :parts, -> { order(:position) }, class_name: "WsjrdpSyncRunPart", foreign_key: :run_id,
    inverse_of: :run, dependent: :destroy

  validates :source, :started_at, presence: true
  validates :status, inclusion: {in: STATES}

  scope :newest_first, -> { order(started_at: :desc, id: :desc) }

  def open? = OPEN.include?(status)

  def cancelled? = status == CANCELLED

  def modified_rows = Wsjrdp::Sync::Stats.of(stats)

  # The time of its phases, in ms.
  def duration_ms = timings.sum { |entry| entry["duration_ms"].to_i }

  # Whether a plan still to write holds a warning (not just a hint).
  def warnings? = parts.any? { |part| part.writable? && part.warnings? }
end
