# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddAdditionalEmailsWsjrdp < ActiveRecord::Migration[7.1]
  def change
    # Update additional_emails
    add_column :additional_emails, :kind, :string, null: true
    add_column :additional_emails, :sepa_mailings, :boolean, default: false, null: false
    add_column :additional_emails, :hidden, :boolean, default: false, null: false
    add_column :additional_emails, :public_is_locked, :boolean, default: false, null: false
    add_column :additional_emails, :mailings_is_locked, :boolean, default: false, null: false
    add_column :additional_emails, :invoices_is_locked, :boolean, default: false, null: false
    add_column :additional_emails, :sepa_mailings_is_locked, :boolean, default: false, null: false
    add_column :additional_emails, :destroy_is_disabled, :boolean, default: false, null: false
    add_column :additional_emails, :position, :integer, default: 0, null: false
    add_column :additional_emails, :additional_info, :jsonb, default: {}
    add_index :additional_emails, [:contactable_id, :contactable_type, :kind], unique: true, where: "(kind IS NULL)", name: "index_additional_emails_on_on_contactable_and_kind"
    reversible do |direction|
      direction.up do
        execute <<-SQL
UPDATE additional_emails SET additional_info = '{}'::jsonb;
        SQL
      end
    end
  end
end
