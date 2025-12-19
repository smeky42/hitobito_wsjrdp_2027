# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class ChangePeopleSepaStatusAndAdditionalContactSingle < ActiveRecord::Migration[7.1]
  def change
    reversible do |direction|
      direction.up do
        execute <<-SQL
UPDATE people SET additional_contact_single = FALSE WHERE additional_contact_single IS NULL;
UPDATE people SET sepa_status = 'ok' WHERE sepa_status IS NULL;
        SQL
      end
    end
    change_column_default :people, :additional_contact_single, from: nil, to: false
    change_column_null :people, :additional_contact_single, false
    change_column_null :people, :sepa_status, false
  end
end



