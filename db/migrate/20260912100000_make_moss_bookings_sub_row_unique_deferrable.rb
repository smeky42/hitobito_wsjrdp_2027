# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# L3 is keyed on (moss_expense_id, sub_row_number): a split is numbered once
# within its expense. A unique index is checked row by row, which makes any
# renumbering of the splits of an expense depend on the order of the writes.
# A unique constraint carries the same uniqueness and is DEFERRABLE INITIALLY
# DEFERRED here: by default the check runs at COMMIT, so a transaction may
# leave the numbering ambiguous between its statements and only has to end on
# a unique assignment. A writer that wants the check back at the end of every
# statement asks for it with
# SET CONSTRAINTS unq_moss_bookings_expense_sub_row IMMEDIATE. The constraint
# name follows the table's own convention for named constraints
# (chk_moss_bookings_*).
class MakeMossBookingsSubRowUniqueDeferrable < ActiveRecord::Migration[7.1]
  INDEX_NAME = "index_moss_bookings_expense_sub_row"
  CONSTRAINT_NAME = "unq_moss_bookings_expense_sub_row"

  def up
    remove_index :moss_bookings, name: INDEX_NAME
    add_unique_constraint :moss_bookings, [:moss_expense_id, :sub_row_number],
      deferrable: :deferred, name: CONSTRAINT_NAME
  end

  def down
    remove_unique_constraint :moss_bookings, name: CONSTRAINT_NAME
    add_index :moss_bookings, [:moss_expense_id, :sub_row_number], unique: true, name: INDEX_NAME
  end
end
