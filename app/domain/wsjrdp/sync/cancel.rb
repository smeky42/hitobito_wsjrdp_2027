# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
module Wsjrdp::Sync
  # Ends a run that has not finished: the parts not yet written are skipped.
  # A run "applying" that has not moved on for STUCK (its request died; Apply
  # touches it after each part) may be cancelled too. Returns whether it was
  # cancelled.
  module Cancel
    STUCK = 10.minutes

    def self.call(run)
      run.with_lock do
        stuck = run.status == WsjrdpSyncRun::APPLYING && run.updated_at < STUCK.ago
        if run.open? || stuck
          run.parts.select(&:writable?).each { |part| part.update!(status: WsjrdpSyncRunPart::SKIPPED) }
          run.update!(status: WsjrdpSyncRun::CANCELLED, finished_at: Time.current)
        end
      end
      run.cancelled?
    end
  end
end
