# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Per-user preferences catch-all on people, analogous to
# additional_info: a jsonb store for per-user settings.
class AddPeopleWsjrdpUserPreferences < ActiveRecord::Migration[7.1]
  def change
    add_column :people, :wsjrdp_user_preferences, :jsonb, null: false, default: {}, comment: "Per-user preferences"
  end
end
