# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddPeopleGroupsAdditionalInfo < ActiveRecord::Migration[7.1]
  def change
    add_column :people, :additional_info, :jsonb, default: {}
    add_column :groups, :additional_info, :jsonb, default: {}
    reversible do |direction|
      direction.up do
        execute <<-SQL
UPDATE people SET additional_info = '{}'::jsonb WHERE additional_info IS NULL;
UPDATE groups SET additional_info = '{}'::jsonb WHERE additional_info IS NULL;
        SQL
      end
    end
  end
end
