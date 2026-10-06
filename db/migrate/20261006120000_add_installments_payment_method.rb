# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddInstallmentsPaymentMethod < ActiveRecord::Migration[7.1]
  def change
    add_column :wsjrdp_payment_plans, :payment_method, :string, null: false, default: "direct_debit"
    add_column :wsjrdp_payment_plans, :deleted_at, :datetime, null: true
    change_column_null :wsjrdp_payment_plans, :single_payment, false
    change_column_null :wsjrdp_payment_plans, :additional_info, false, {}
    remove_index :wsjrdp_payment_plans, [:wsjrdp_role, :single_payment], unique: true,
      name: "index_wsjrdp_payment_plans_wsjrdp_role_single_payment"
    add_index :wsjrdp_payment_plans, [:wsjrdp_role, :single_payment, :payment_method], unique: true,
      where: "deleted_at IS NULL",
      name: "index_wsjrdp_payment_plans_role_single_payment_method"

    add_column :wsj27_rdp_fee_rules, :custom_installments_payment_method, :string, null: true
    add_reference :wsj27_rdp_fee_rules, :custom_installments_payment_plan, type: :integer, null: true,
      foreign_key: {to_table: :wsjrdp_payment_plans},
      index: {name: "index_wsj27_rdp_fee_rules_on_payment_plan_id"}
    add_column :wsj27_rdp_fee_rules, :additional_info, :jsonb, default: {}, null: false

    add_column :people, :wsjrdp_installments_payment_method, :string, null: true
    add_reference :people, :wsjrdp_installments_payment_plan, type: :integer, null: true,
      foreign_key: {to_table: :wsjrdp_payment_plans}

    reversible do |direction|
      direction.up do
        execute <<~SQL
          UPDATE wsj27_rdp_fee_rules
             SET custom_installments_payment_method = 'direct_debit'
           WHERE custom_installments_starting_year IS NOT NULL
             AND custom_installments_cents IS NOT NULL
        SQL
        execute <<~SQL
          UPDATE people
             SET wsjrdp_installments_payment_method = 'direct_debit'
           WHERE wsjrdp_raw_installments_eur IS NOT NULL
        SQL
      end
    end

    add_check_constraint :wsj27_rdp_fee_rules,
      "(custom_installments_payment_method IS NULL) = " \
      "(custom_installments_starting_year IS NULL OR custom_installments_cents IS NULL)",
      name: "chk_wsj27_rdp_fee_rules_payment_method_iff_plan"
    add_check_constraint :people,
      "(wsjrdp_installments_payment_method IS NULL) = (wsjrdp_raw_installments_eur IS NULL)",
      name: "chk_people_wsjrdp_installments_payment_method_iff_plan"
  end
end
