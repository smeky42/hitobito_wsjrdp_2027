# frozen_string_literal: true

#  Copyright (c) 2025, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

class AddPeopleAttrsAdditionalContact < ActiveRecord::Migration[4.2]
    def change
      add_column :people, :additional_contact_name_a, :string
      add_column :people, :additional_contact_adress_a, :string
      add_column :people, :additional_contact_email_a, :string
      add_column :people, :additional_contact_phone_a, :string
      add_column :people, :additional_contact_name_b, :string
      add_column :people, :additional_contact_adress_b, :string
      add_column :people, :additional_contact_email_b, :string
      add_column :people, :additional_contact_phone_b, :string
      add_column :people, :additional_contact_single, :boolean
    end
end
