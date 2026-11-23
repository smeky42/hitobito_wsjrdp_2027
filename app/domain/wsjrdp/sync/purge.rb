# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
module Wsjrdp::Sync
  # Deletes the files of runs older than KEEP and notes it on their parts.
  # The runs, their plans and counts stay.
  module Purge
    KEEP = 90.days

    # How many files were deleted.
    def self.call(now: Time.current)
      before = now - KEEP
      deleted = Files.purge(before: before)
      WsjrdpSyncRunPart.joins(:run).where(files_purged_at: nil).where(wsjrdp_sync_runs: {started_at: ...before})
        .update_all(files_purged_at: now)
      deleted
    end
  end
end
