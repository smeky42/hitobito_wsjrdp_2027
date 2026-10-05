# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddContributionSubjectLinkMetaToMossBookings < ActiveRecord::Migration[7.1]
  def change
    add_column :moss_bookings, :contribution_subject_link_meta, :jsonb, default: {}, null: false
  end
end
