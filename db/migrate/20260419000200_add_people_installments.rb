# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddPeopleInstallments < ActiveRecord::Migration[7.1]
  def change
    add_column :people, "wsjrdp_total_fee_reduction", :decimal, precision: 20, scale: 3, null: false, default: 0
    add_column :people, "wsjrdp_total_fee_reduction_issue", :string
    add_column :people, "wsjrdp_total_fee_reduction_hint", :text
    add_column :people, "wsjrdp_total_fee_reduction_comment", :text
    add_column :people, "wsjrdp_raw_installments_eur", :decimal, precision: 20, scale: 3, array: true
    add_column :people, "wsjrdp_installments_issue", :string
    add_column :people, "wsjrdp_installments_comment", :text
  end
end
