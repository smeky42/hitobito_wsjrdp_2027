# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A row copied from the Moss API (MossDepartment, MossTeam, MossUser). A row
# Moss no longer returns stays, marked by `moss_removed_at`; `.in_moss` hides
# it.
module MossSyncedRecord
  extend ActiveSupport::Concern

  included do
    scope :in_moss, -> { where(moss_removed_at: nil) }
    scope :removed_from_moss, -> { where.not(moss_removed_at: nil) }
  end

  def removed_from_moss? = moss_removed_at.present?
end
