# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class ChangeAccountingAddAdditionalInfo < ActiveRecord::Migration[7.1]

  def change
    # update accounting_entries
    rename_column :accounting_entries, :end_to_end_identifier, :endtoend_id
    change_column_null :accounting_entries, :description, false
    change_column_comment :accounting_entries, :debit_sequence_type, from: nil, to: "SEPA direct debit sequence type"
    add_column :accounting_entries, :pre_notified_amount_cents, :integer, null: true
    add_column :accounting_entries, :creditor_id, :string, null: true
    add_column :accounting_entries, :additional_info, :jsonb, default: {}
    reversible do |direction|
      change_table :accounting_entries do |t|
        direction.up   { t.change :description, :string }
        direction.down { t.change :description, :text }
      end
    end
    reversible do |direction|
      direction.up do
        execute "UPDATE accounting_entries SET additional_info = '{}'::jsonb WHERE additional_info IS NULL;"
      end
    end

    # update wsjrdp_direct_debit_payment_infos
    rename_column :wsjrdp_direct_debit_payment_infos, :sequence_type, :debit_sequence_type
    rename_column :wsjrdp_direct_debit_payment_infos, :control_sum, :control_sum_cents
    add_column :wsjrdp_direct_debit_payment_infos, :cdtr_address, :string, null: true
    reversible do |direction|
      direction.up do
        execute "UPDATE wsjrdp_direct_debit_payment_infos SET cdtr_address = 'Chausseestraße 128/129, 10115 Berlin' WHERE cdtr_address IS NULL;"
      end
    end

    # update wsjrdp_direct_debit_pre_notifications
    reversible do |direction|
      direction.up do
        execute "UPDATE wsjrdp_direct_debit_pre_notifications SET try_skip = FALSE WHERE try_skip IS NULL;"
      end
    end
    change_column_default :wsjrdp_direct_debit_pre_notifications, :try_skip, from: nil, to: false
    change_column_null :wsjrdp_direct_debit_pre_notifications, :try_skip, false
    change_column_default :wsjrdp_direct_debit_pre_notifications, :email_from, from: "anmeldung@worldscoutjamboree.de", to: "info@worldscoutjamboree.de"
    change_column_null :wsjrdp_direct_debit_pre_notifications, :description, false
    rename_column :wsjrdp_direct_debit_pre_notifications, :sequence_type, :debit_sequence_type
    add_column :wsjrdp_direct_debit_pre_notifications, :pre_notified_amount_cents, :integer, null: true
    add_column :wsjrdp_direct_debit_pre_notifications, :comment, :text, null: false, default: ""
    add_column :wsjrdp_direct_debit_pre_notifications, :cdtr_name, :string, null: false, default: "Ring deutscher Pfadfinder*innenverbände e.V."
    add_column :wsjrdp_direct_debit_pre_notifications, :cdtr_iban, :string, null: false, default: "DE13370601932001939044"
    add_column :wsjrdp_direct_debit_pre_notifications, :cdtr_bic, :string, null: false, default: "GENODED1PAX"
    add_column :wsjrdp_direct_debit_pre_notifications, :cdtr_address, :string, null: false, default: "Chausseestraße 128/129, 10115 Berlin"
    add_column :wsjrdp_direct_debit_pre_notifications, :additional_info, :jsonb, null: false, default: {}
    reversible do |direction|
      direction.up do
        execute <<-SQL
UPDATE wsjrdp_direct_debit_pre_notifications SET cdtr_name = 'Ring deutscher Pfadfinder*innenverbände e.V.' WHERE cdtr_name IS NULL;
UPDATE wsjrdp_direct_debit_pre_notifications SET cdtr_iban = 'DE13370601932001939044' WHERE cdtr_iban IS NULL;
UPDATE wsjrdp_direct_debit_pre_notifications SET cdtr_bic = 'GENODED1PAX' WHERE cdtr_bic IS NULL;
UPDATE wsjrdp_direct_debit_pre_notifications SET cdtr_address = 'Chausseestraße 128/129, 10115 Berlin' WHERE cdtr_address IS NULL;
UPDATE wsjrdp_direct_debit_pre_notifications SET pre_notified_amount_cents = amount_cents WHERE pre_notified_amount_cents IS NULL;
UPDATE wsjrdp_direct_debit_pre_notifications SET additional_info = '{}'::jsonb WHERE additional_info IS NULL;
        SQL
      end
    end

    # update wsjrdp_payment_initiations
    add_column :wsjrdp_payment_initiations, :additional_info, :jsonb, default: {}
    rename_column :wsjrdp_payment_initiations, :control_sum, :control_sum_cents
    reversible do |direction|
      direction.up do
        execute "UPDATE wsjrdp_payment_initiations SET additional_info = '{}'::jsonb WHERE additional_info IS NULL;"
      end
    end
  end
end
