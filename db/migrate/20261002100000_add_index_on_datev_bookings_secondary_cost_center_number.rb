# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A unit's detail, its Gesamtausgaben and the filter "Kostenstelle oder
# sekundäre Kostenstelle" ask `cost_center_number = X OR
# secondary_cost_center_number = X`; with an index on either column PostgreSQL
# answers that with a bitmap OR instead of reading the whole table.
class AddIndexOnDatevBookingsSecondaryCostCenterNumber < ActiveRecord::Migration[7.1]
  def change
    add_index :datev_bookings, :secondary_cost_center_number
  end
end
