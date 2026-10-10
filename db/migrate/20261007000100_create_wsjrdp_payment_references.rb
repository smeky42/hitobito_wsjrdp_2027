# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class CreateWsjrdpPaymentReferences < ActiveRecord::Migration[7.1]
  def change
    create_table :wsjrdp_payment_references do |t|
      # The form of payment_code; for rf it is RF, two check digits and the
      # codeword.
      t.string :payment_code_type, null: false, default: "rf"
      # The code as the remittance information carries it, and its codeword.
      t.string :payment_code, null: false
      t.string :codeword, null: false
      # How the codeword is made: its scheme, its lengths and the
      # Reed-Solomon code over GF(2^rs_field_exponent).
      t.string :codeword_scheme, null: false, default: "crockford_rs"
      t.integer :data_length, null: false, default: 8
      t.integer :parity_length, null: false, default: 4
      t.integer :rs_field_exponent, null: false, default: 5
      t.integer :rs_primitive_polynomial, null: false, default: 0x25
      t.integer :rs_generator, null: false, default: 2
      t.integer :rs_fcr, null: false, default: 1
      t.string :status, null: false, default: "available"
      t.datetime :assigned_at, null: true
      # Who made the code: script or wagon.
      t.string :origin, null: false, default: "script"
      t.text :comment, null: false, default: ""
      t.jsonb :additional_info, null: false, default: {}
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :updated_at, null: true

      t.index :payment_code, unique: true
      t.index :codeword, unique: true
      t.index [:status, :id]
      t.check_constraint "payment_code_type <> 'rf' OR (left(payment_code, 2) = 'RF' " \
        "AND substr(payment_code, 3, 2) ~ '^[0-9]{2}$' AND substr(payment_code, 5) = codeword)",
        name: "chk_wsjrdp_payment_references_rf_form"
    end

    # The payment reference a notice's payment_code comes from, if any.
    add_reference :wsjrdp_payment_notices, :payment_reference, null: true,
      foreign_key: {to_table: :wsjrdp_payment_references, on_delete: :restrict}
  end
end
