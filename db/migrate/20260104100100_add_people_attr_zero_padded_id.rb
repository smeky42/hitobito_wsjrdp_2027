# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddPeopleAttrZeroPaddedId < ActiveRecord::Migration[7.1]
  def change
    add_column :people, :zero_padded_id, :string,
               as: %q{CASE WHEN char_length("id"::VARCHAR) < 4 THEN lpad("id"::VARCHAR, 4, '0') ELSE "id"::VARCHAR END},
               stored: true
  end
end
