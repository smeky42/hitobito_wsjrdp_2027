# frozen_text_literal: true

class AddPeopleCustomInstallments < ActiveRecord::Migration[7.1]
  def change
    add_column :people, :custom_installments_issue, :string, null: true,
               comment: 'Link to helpdesk issue agreeing the custom installments, used in custom contract'
    add_column :people, :custom_installments_year, :integer, null: true,
               comment: 'starting year for entires in custom_installments'
    add_column :people, :custom_installments_cents, :integer, null: true, array: true,
               comment: 'list of custom monthly installments starting in January of custom_installments_year'
    add_column :people, :total_fee_reduction_comment, :string, null: true,
               comment: 'Comment explaining the total fee reduction'
    add_column :people, :total_fee_reduction_cents, :integer, default: 0,
               comment: 'Reduction of the total fee in cents'
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
