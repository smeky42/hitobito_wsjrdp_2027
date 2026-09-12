# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# L2 is keyed on (moss_transaction_id, expense_number): an expense is
# numbered once within its transaction. A unique index is checked row
# by row, so a single UPDATE that exchanges the numbers of two
# expenses of a reimbursement collides on the row it writes first. A
# unique constraint carries the same uniqueness and is DEFERRABLE
# INITIALLY DEFERRED here: the check runs at COMMIT, so a transaction
# may leave the numbering ambiguous between its statements and only
# has to end on a unique assignment; every other writer sees it at
# COMMIT.
class MakeMossExpensesExpenseNumberDeferrable < ActiveRecord::Migration[7.1]
  def change
    remove_index :moss_expenses, [:moss_transaction_id, :expense_number],
      unique: true, name: "index_moss_expenses_transaction_expense_number"
    add_unique_constraint :moss_expenses, [:moss_transaction_id, :expense_number],
      deferrable: :deferred, name: "unq_moss_expenses_transaction_expense_number"
  end
end
