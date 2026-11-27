# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class CreateMossMasterDataTables < ActiveRecord::Migration[7.1]
  MOSS_ORGANISATION_UUID = "ee55d234-7890-4bd2-8617-5f2f4c1d605a"

  def change
    create_table :moss_payment_terms, comment: "Moss payment terms (API /v1/payment-terms)" do |t|
      t.uuid :moss_payment_term_uuid, null: false, comment: "API field `id`"
      t.uuid :moss_organisation_uuid, default: MOSS_ORGANISATION_UUID, comment: "API field `organisationId`"
      t.string :description, comment: "API field `description`"
      t.string :code, comment: "API field `code`: the reference in the accounting system"
      t.integer :net_due_days, comment: "API field `netDueDays`"
      t.integer :month_end_advances, comment: "API field `monthEndAdvances`"
      t.string :due_date_calculation_type, comment: "API field `dueDateCalculationType`"
      t.string :status, comment: "API field `status`"
      t.jsonb :lines, null: false, default: [], comment: "API field `lines`: the early-payment discount tiers"
      sync_columns(t)
      t.timestamps
      t.index :moss_payment_term_uuid, unique: true
    end

    create_table :moss_tax_rates, comment: "Moss tax rates (API /v1/tax-rates)" do |t|
      t.uuid :moss_tax_rate_uuid, null: false, comment: "API field `id`"
      t.uuid :moss_organisation_uuid, default: MOSS_ORGANISATION_UUID, comment: "API field `organisationId`"
      t.string :tax_type, comment: "API field `type`: VAT, ..."
      t.string :country, comment: "API field `country` (ISO 3166-1 alpha-2)"
      t.string :name, comment: "API field `name`"
      t.decimal :rate, precision: 9, scale: 4, comment: "API field `rate`, in percent"
      t.string :code, comment: "API field `code`: the tax code in the accounting system"
      t.boolean :reverse_charge, comment: "API field `reverseCharge`"
      t.string :status, comment: "API field `status`: ACTIVE, INACTIVE, ..."
      t.datetime :moss_created_at, comment: "API field `createTime`"
      t.datetime :moss_updated_at, comment: "API field `updateTime`"
      sync_columns(t)
      t.timestamps
      t.index :moss_tax_rate_uuid, unique: true
    end

    {default_moss_payment_term_uuid: "Moss supplier API field `paymentTermId`",
     default_moss_vat_rate_uuid: "Moss supplier API field `defaultVatRateId`"}.each do |column, comment|
      add_column :wsjrdp_personal_accounts, column, :uuid, comment: comment
      add_index :wsjrdp_personal_accounts, column, where: "#{column} IS NOT NULL",
        name: "index_personal_accounts_on_#{column}"
    end
  end

  private

  def sync_columns(t)
    t.datetime :last_seen_at, comment: "Last sync that returned the row"
    t.datetime :moss_removed_at, comment: "Set when a sync no longer returned the row; cleared when it comes back"
    t.text :comment, null: false, default: "", comment: "Hitobito's own note on the row"
    t.jsonb :additional_info, null: false, default: {}
  end
end
