# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
module Wsjrdp::Sync
  # Records a phase of a run or a part in its timings: start and end, the
  # duration, and its status -- "succeeded", "failed" (with error_message)
  # or what the block sets (e.g. "stale"; it gets the entry). The owner is
  # saved later.
  module Timing
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    STALE = "stale"

    def self.record(owner, phase)
      entry = {"phase" => phase, "started_at" => Time.current.utc.iso8601(3)}
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield entry
    rescue => e
      entry["status"] = FAILED
      entry["error_message"] = Wsjrdp::Sync.error_text(e)
      raise
    ensure
      entry["status"] ||= SUCCEEDED
      entry["finished_at"] = Time.current.utc.iso8601(3)
      entry["duration_ms"] = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      owner.timings = owner.timings + [entry]
    end
  end
end
