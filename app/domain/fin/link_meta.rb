# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The *_link_meta objects of the finance links (doc/fin/recon_linking.md §1/§3).
module Fin::LinkMeta
  # A link made by hand in the UI: who and when, "manual", no score and no
  # classification -- a hand pick, not an import-equivalent rule.
  def self.manual(author_id:, now: Time.zone.now)
    {"created_at" => now.iso8601, "author_id" => author_id, "score" => nil,
     "automatic_manual" => "manual", "classification_string" => nil}
  end
end
