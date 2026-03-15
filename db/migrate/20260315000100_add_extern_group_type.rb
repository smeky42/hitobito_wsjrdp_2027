# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddExternGroupType < ActiveRecord::Migration[7.1]
  def change
    add_column :groups, :is_wsjrdp, :boolean, default: true, null: false
    reversible do |direction|
      direction.up do
        execute "INSERT INTO group_type_orders (name, order_weight, created_at, updated_at) VALUES ('Group::Extern', 4, NOW(), NOW());"
        execute "UPDATE groups SET is_wsjrdp = TRUE WHERE id NOT IN (5, 6, 7, 45, 46);"
        execute "UPDATE groups SET is_wsjrdp = FALSE WHERE id IN (5, 6, 7, 45, 46);"
      end
      direction.down do
        execute "DELETE FROM group_type_orders WHERE name = 'Group::Extern';"
      end
    end
  end
end

