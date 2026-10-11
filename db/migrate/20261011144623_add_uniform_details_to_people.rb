# frozen_string_literal: true

#  Copyright (c) 2026, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

class AddUniformDetailsToPeople < ActiveRecord::Migration[6.1]
  def change
    add_column :people, :uniform_long_sleeve, :boolean
    add_column :people, :uniform_order, :boolean
    add_column :people, :headgear, :string
  end
end
