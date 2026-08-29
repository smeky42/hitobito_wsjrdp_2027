# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Give a bank transaction the same cost-accounting classification and DATEV
# posting metadata that a datev_bookings row carries.

class AddDatevFieldsToWsjrdpCamtTransactions < ActiveRecord::Migration[7.1]
  def change
    change_table :wsjrdp_camt_transactions do |t|
      # Cost center/sphere
      t.string :cost_center_number, null: true
      t.string :sphere_number, null: true, default: "3", comment: "Tax sphere (steuerliche Sphäre)"

      # Polymorphic account references (WsjrdpLedgerAccount / WsjrdpPersonalAccount)
      t.bigint :account_id, null: true
      t.string :account_type, null: true
      t.bigint :offsetting_account_id, null: true
      t.string :offsetting_account_type, null: true

      # DATEV posting metadata
      t.string :datev_posting_text, null: true, comment: "DATEV Buchungstext"
      t.string :datev_document_field_1, null: true, comment: "DATEV Belegfeld 1"
      t.string :datev_document_field_2, null: true, comment: "DATEV Belegfeld 2"
      t.jsonb :datev_beleginfo, null: false, default: [],
        comment: "DATEV Beleginfo as [{num,key,value}] (like datev_bookings.beleginfo)"
      t.jsonb :datev_zusatzinformation, null: false, default: [],
        comment: "DATEV Zusatzinformation as [{num,key,value}] (like datev_bookings.zusatzinformation)"

      # The DATEV Buchungsstapel this transaction was posted in, plus when that
      # batch was exported from DATEV.
      t.references :datev_booking_batch, null: true, foreign_key: true, comment: "Optional n:1 (<-> datev_booking_batches)"
    end
  end
end
