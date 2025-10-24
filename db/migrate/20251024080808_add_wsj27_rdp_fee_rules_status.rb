# frozen_text_literal: true

class AddWsj27RdpFeeRulesStatus < ActiveRecord::Migration[7.1]
  def change
    # status: 'planned', 'active', 'deleted'
    add_column :wsj27_rdp_fee_rules, :status, :string, null: false, default: "planned"
    add_column :wsj27_rdp_fee_rules, :activated_at, :datetime, null: true
    add_index :wsj27_rdp_fee_rules, [:people_id, :status], unique: true, where: "deleted_at IS NULL"
  end
end
