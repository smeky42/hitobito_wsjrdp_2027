# frozen_text_literal: true

class AddWsj27RdpFeeRules < ActiveRecord::Migration[7.1]
  def change
    create_table  :wsj27_rdp_fee_rules do |t|
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: true
      t.datetime :deleted_at, null: true
      t.belongs_to :people, null: true
      t.belongs_to :prev_rule, null: true, foreign_key: { to_table: :wsj27_rdp_fee_rules },
                   comment: 'Previous (now marked as deleted) rule if any, to be used if installment plans and/or total fee reductions are updated'
      t.string :custom_installments_comment, null: true
      t.string :custom_installments_issue, null: true,
               comment: 'Link to helpdesk issue agreeing the custom installments, used in custom contract'
      t.integer :custom_installments_starting_year, null: true,
                comment: 'starting year for entires in custom_installments_cents'
      t.integer :custom_installments_cents, null: true, array: true,
                comment: 'list of custom monthly installments starting in January of custom_installments_year'
      t.string :total_fee_reduction_comment, null: true,
               comment: 'Comment explaining the total fee reduction'
      t.integer :total_fee_reduction_cents, default: 0,
                comment: 'Reduction of the total fee in cents'
    end
  end
end

# A custom installment plan of monthly 200 EUR starting in January
# 2026 would be encoded like this:
#
# custom_installments_issue = 'HELP-XYZ'
# custom_installments_year = 2026
# custom_installments_cents = [20000, 20000, ..., 20000] -- 17 entries
#
# A custom intallment plan with a 50% installment in August 2025 and
# the rest in May 2026 would be encoded like this:
#
# custom_installments_issue = 'HELP-XYZ'
# custom_installments_year = 2025
# custom_intallments_cents = [0, 0, 0, 0, 0, 0, 0, 170000, 0, 0, 0, 0, 0, 0, 0, 0, 170000]
#                             ^                    ^                               ^
#                             |                    |                               |
#             January 2025 ---+               August 2025                       May 2026
