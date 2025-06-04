# frozen_string_literal: true

#  Copyright (c) 2025, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

class AddPeopleAttrsUpload < ActiveRecord::Migration[4.2]
    def change
      add_column :people, :upload_contract_pdf, :string
      add_column :people, :upload_data_agreement_pdf, :string
      add_column :people, :upload_passport_pdf, :string
      add_column :people, :upload_good_conduct_pdf, :string
    end
end
