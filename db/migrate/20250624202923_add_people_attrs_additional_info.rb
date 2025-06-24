# frozen_string_literal: true

#  Copyright (c) 2025, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

class AddPeopleAttrsAdditionalInfo < ActiveRecord::Migration[4.2]
  def change
    add_column :people, :pronoun, :string, default: ""

    add_column :people, :passport_germany, :boolean
    add_column :people, :passport_nationality, :string
    add_column :people, :passport_approved, :bool, default: false

    add_column :people, :languages_spoken, :string
    add_column :people, :shirt_size, :string
    add_column :people, :uniform_size, :string
    add_column :people, :can_swim, :boolean
  end
end
