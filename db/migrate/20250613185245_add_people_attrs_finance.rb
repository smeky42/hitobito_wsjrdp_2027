# frozen_string_literal: true

#  Copyright (c) 2025, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

class AddPeopleAttrsFinance < ActiveRecord::Migration[4.2]
  def change
    add_column :people, :sepa_name, :string
    add_column :people, :sepa_address, :string
    add_column :people, :sepa_mail, :string
    add_column :people, :sepa_iban, :string
    add_column :people, :sepa_bic, :string
    add_column :people, :sepa_status, :string
    add_column :people, :early_payer, :boolean
  end
end
