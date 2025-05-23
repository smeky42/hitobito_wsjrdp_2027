# frozen_string_literal: true

#  Copyright (c) 2025, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

class AddPeopleAttrsPreReg < ActiveRecord::Migration[4.2]
  def change
    add_column :people, :rdp_association, :string
    add_column :people, :rdp_association_region, :string
    add_column :people, :rdp_association_sub_region, :string
    add_column :people, :rdp_association_group, :string
    add_column :people, :rdp_association_number, :string
  end
end
