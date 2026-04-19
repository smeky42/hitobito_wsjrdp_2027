# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddWsjrdpPaymentPlans < ActiveRecord::Migration[7.1]
  def change
    create_table "wsjrdp_payment_plans", id: :serial, force: :cascade do |t|
      t.datetime "created_at", null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.datetime "updated_at", null: true
      t.text "comment", default: "", null: false
      t.string "status", null: true
      t.jsonb "additional_info", default: {}
      t.string "wsjrdp_role", null: false
      t.boolean "single_payment", null: true
      t.decimal "raw_installments_eur", precision: 20, scale: 3, array: true
      t.index ["wsjrdp_role", "single_payment"], name: "index_wsjrdp_payment_plans_wsjrdp_role_single_payment", unique: true
    end

    reversible do |direction|
      direction.up do
        execute <<-SQL
INSERT INTO wsjrdp_payment_plans (wsjrdp_role, single_payment, raw_installments_eur) VALUES
('YP',  FALSE, ARRAY[2025, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 300, 500, 500, 500, 0, 0, 0, 0, 400, 0, 0, 400, 0, 0, 400, 0, 0, 400]),
('YP',  TRUE,  ARRAY[2025, 0, 0, 0, 0, 0, 0, 0, 3400]),
('UL',  FALSE, ARRAY[2025, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 150, 350, 350, 350, 0, 0, 0, 0, 300, 0, 0, 300, 0, 0, 300, 0, 0, 300]),
('UL',  TRUE,  ARRAY[2025, 0, 0, 0, 0, 0, 0, 0, 2400]),
('IST', FALSE, ARRAY[2025, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 200, 400, 400, 400, 0, 0, 0, 0, 300, 0, 0, 300, 0, 0, 300, 0, 0, 300]),
('IST', TRUE,  ARRAY[2025, 0, 0, 0, 0, 0, 0, 0, 2600]),
('BMT', FALSE, ARRAY[2025, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 200, 400, 400, 400, 0, 0, 0, 0, 300, 0, 0, 300, 0, 0, 300, 0, 0, 300]),
('BMT', TRUE,  ARRAY[2025, 0, 0, 0, 0, 0, 0, 0, 2600]),
('CMT', FALSE, ARRAY[2025, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 50, 250, 250, 250, 0, 0, 0, 0, 200, 0, 0, 200, 0, 0, 200, 0, 0, 200]),
('CMT', TRUE,  ARRAY[2025, 0, 0, 0, 0, 0, 0, 0, 1600]),
('EXT', FALSE, ARRAY[]::decimal[]),
('EXT', TRUE,  ARRAY[]::decimal[])
        SQL
      end
    end
  end
end
