# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddWsjrdpInternalTransfers < ActiveRecord::Migration[7.1]
  def change
    create_table :wsjrdp_internal_transfers, comment: "Linking internal transfers" do |t|
      t.text :comment, default: '', null: false
      t.jsonb :link_meta, null: false, default: {}
      t.jsonb :additional_info, null: false, default: {}
      t.timestamps
    end

    add_reference :wsjrdp_camt_transactions, :internal_transfer, null: true,
      foreign_key: {to_table: :wsjrdp_internal_transfers, on_delete: :nullify},
      index: {where: "internal_transfer_id IS NOT NULL"}
    add_reference :moss_transactions, :internal_transfer, null: true,
      foreign_key: {to_table: :wsjrdp_internal_transfers, on_delete: :nullify},
      index: {where: "internal_transfer_id IS NOT NULL"}

    add_column :wsjrdp_fin_accounts, :top_up_iban, :string, null: true
    add_column :wsjrdp_fin_accounts, :top_up_bic, :string, null: true
    add_column :wsjrdp_fin_accounts, :top_up_purpose, :string, null: true
    add_column :wsjrdp_fin_accounts, :top_up_recipient_name, :string, null: true
  end
end
