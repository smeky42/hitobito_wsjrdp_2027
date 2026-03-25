# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddPeopleAttrsWsjRole < ActiveRecord::Migration[7.1]
  def change
    add_column :people, :wsj_role, :string, null: true
    reversible do |direction|
      direction.up do
        execute <<-SQL
UPDATE people SET wsj_role = 'UL' WHERE wsj_role IS NULL AND payment_role LIKE '%::Unit::Leader';
UPDATE people SET wsj_role = 'YP' WHERE wsj_role IS NULL AND payment_role LIKE '%::Unit::Member';
UPDATE people SET wsj_role = 'IST' WHERE wsj_role IS NULL AND payment_role LIKE '%::Ist::Member';
UPDATE people SET wsj_role = 'CMT' WHERE wsj_role IS NULL AND payment_role LIKE '%::Root::Member';
UPDATE people SET wsj_role = 'EXT' WHERE wsj_role IS NULL AND payment_role LIKE '%::Extern::Member';
UPDATE people SET wsj_role = 'EXT' WHERE wsj_role IS NULL AND id = 1;  -- admin account
UPDATE people SET wsj_role = 'UL' WHERE wsj_role IS NULL AND primary_group_id = 5; -- UL Warteliste
UPDATE people SET wsj_role = 'YP' WHERE wsj_role IS NULL AND primary_group_id = 6; -- YP Warteliste
UPDATE people SET wsj_role = 'IST' WHERE wsj_role IS NULL AND primary_group_id IN (7, 45); -- IST Warteliste / BMT
UPDATE people SET wsj_role = 'EXT' WHERE wsj_role IS NULL AND primary_group_id = 48; -- Externe Mitarbeitende
-- fill-in early_payer when people are beyond registered
UPDATE people SET early_payer = FALSE WHERE early_payer IS NULL AND status <> 'registered';
-- fill-in payment_role
UPDATE people SET payment_role = 'RegularPayer::Group::Extern::Member' WHERE payment_role IS NULL AND wsj_role = 'EXT';
UPDATE people SET payment_role = 'EarlyPayer::Group::Unit::Leader' WHERE payment_role IS NULL AND early_payer = TRUE AND primary_group_id = 5; -- UL Warteliste
UPDATE people SET payment_role = 'RegularPayer::Group::Unit::Leader' WHERE payment_role IS NULL AND primary_group_id = 5; -- UL Warteliste
UPDATE people SET payment_role = 'EarlyPayer::Group::Unit::Member' WHERE payment_role IS NULL AND early_payer = TRUE AND primary_group_id = 6; -- YP Warteliste
UPDATE people SET payment_role = 'RegularPayer::Group::Unit::Member' WHERE payment_role IS NULL AND primary_group_id = 6; -- YP Warteliste
UPDATE people SET payment_role = 'EarlyPayer::Group::Ist::Member' WHERE payment_role IS NULL AND early_payer = TRUE AND primary_group_id IN (7, 45); -- IST Warteliste / BMT
UPDATE people SET payment_role = 'RegularPayer::Group::Ist::Member' WHERE payment_role IS NULL AND primary_group_id IN (7, 45); -- IST Warteliste / BMT
        SQL
      end
      direction.down do
      end
    end
  end
end
