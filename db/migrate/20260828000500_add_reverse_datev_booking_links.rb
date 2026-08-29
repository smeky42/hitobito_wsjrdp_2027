# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddReverseDatevBookingLinks < ActiveRecord::Migration[7.1]
  def change
    # accounting_entries: booking<->entry link (1:1)
    add_column :accounting_entries, :datev_booking_id, :bigint, null: true,
      comment: "Optional 1:1 (<-> datev_bookings)"
    add_column :accounting_entries, :datev_booking_link_meta, :jsonb, null: false, default: {}
    add_index :accounting_entries, :datev_booking_id, unique: true,
      name: "index_accounting_entries_on_datev_booking_id"
    add_foreign_key :accounting_entries, :datev_bookings, column: :datev_booking_id, on_delete: :nullify

    # wsjrdp_camt_transactions: booking<->camt link (1:1).
    add_column :wsjrdp_camt_transactions, :datev_booking_id, :bigint, null: true,
      comment: "Optional 1:1 (<-> datev_bookings)"
    add_column :wsjrdp_camt_transactions, :datev_booking_link_meta, :jsonb, null: false, default: {}
    add_index :wsjrdp_camt_transactions, :datev_booking_id, unique: true,
      name: "index_wsjrdp_camt_transactions_on_datev_booking_id"
    add_foreign_key :wsjrdp_camt_transactions, :datev_bookings, column: :datev_booking_id, on_delete: :nullify
  end
end
