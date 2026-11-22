# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class CreateMossOrganisationTables < ActiveRecord::Migration[7.1]
  # The contingent's one Moss organisation (API field `organisationId`).
  MOSS_ORGANISATION_UUID = "ee55d234-7890-4bd2-8617-5f2f4c1d605a"

  MOSS_UUID_COMMENTS = {
    wsjrdp_ledger_accounts: "Moss expense account UUID (API /v1/expense-accounts, field `id`)",
    wsjrdp_cost_centers: "Moss cost center UUID (Moss dimension item, field `id`)",
    wsjrdp_spheres: "Moss cost carrier UUID (Moss dimension item, field `id`)"
  }.freeze

  # The comment each moss_status column had, so the change can be reverted.
  MOSS_STATUS_COMMENTS = {
    wsjrdp_ledger_accounts: "active or deactivated; NULL = unknown to Moss (counts as deactivated)",
    wsjrdp_personal_accounts: "Moss Status active or deactivated; NULL = unknown to Moss (counts as deactivated)",
    wsjrdp_cost_centers: "Moss Status: active or deactivated; NULL = unknown to Moss (counts as deactivated)",
    wsjrdp_spheres: "Moss Status: active or deactivated; NULL = unknown to Moss (counts as deactivated)"
  }.freeze

  def change
    create_table :moss_departments, comment: "Moss departments (API /v1/departments)" do |t|
      t.uuid :moss_department_uuid, null: false, comment: "Moss department id (API field `id`)"
      organisation_column(t)
      t.uuid :owner_uuid, comment: "Moss user owning the department (API field `ownerId`)"
      t.string :name, comment: "API field `name`"
      sync_columns(t)
      t.timestamps
      t.index :moss_department_uuid, unique: true
      t.index :owner_uuid
    end

    create_table :moss_teams, comment: "Moss teams (API /v1/teams)" do |t|
      t.uuid :moss_team_uuid, null: false, comment: "Moss team id (API field `id`)"
      organisation_column(t)
      t.uuid :moss_department_uuid, comment: "Moss department of the team (API field `departmentId`)"
      t.uuid :team_lead_uuid, comment: "Moss user leading the team (API field `teamLeadId`)"
      t.string :name, comment: "API field `name`"
      t.string :status, comment: "API field `status`: ACTIVE, ARCHIVED, ..."
      sync_columns(t)
      t.timestamps
      t.index :moss_team_uuid, unique: true
      t.index :moss_department_uuid
      t.index :team_lead_uuid
    end

    create_table :moss_users, comment: "Moss users (API /v1/users); mostly one per person" do |t|
      t.uuid :moss_user_uuid, null: false, comment: "Moss user id (API field `id`)"
      organisation_column(t)
      t.uuid :moss_team_uuid, comment: "Moss team of the user (API field `teamId`)"
      t.uuid :manager_uuid, comment: "Moss user managing the user (API field `managerId`)"
      t.references :person, null: true, foreign_key: {on_delete: :nullify},
        comment: "Hitobito person behind the Moss user; several Moss users may share one"
      t.string :email, comment: "API field `email`"
      t.string :first_name, comment: "API field `firstName`"
      t.string :last_name, comment: "API field `lastName`"
      t.string :phone, comment: "CSV user export column `phone`; not in the API"
      t.string :status, comment: "API field `status`: INVITED, ACTIVE, DEACTIVATED, ..."
      t.string :roles, array: true, null: false, default: [], comment: "API field `roles`: USER, TEAMLEAD, ..."
      t.datetime :moss_created_at, comment: "API field `createTime`"
      t.datetime :moss_updated_at, comment: "API field `updateTime`"
      sync_columns(t)
      t.timestamps
      t.index :moss_user_uuid, unique: true
      t.index :moss_team_uuid
      t.index :manager_uuid
      t.index "LOWER(email)", name: "index_moss_users_on_lower_email"
    end

    # Moss dimensions (API /v1/dimensions). Their items are not a table of
    # their own: the cost center items are wsjrdp_cost_centers, the cost carrier
    # items wsjrdp_spheres (by moss_uuid).
    create_table :moss_dimensions, comment: "Moss dimensions (API /v1/dimensions)" do |t|
      t.uuid :moss_dimension_uuid, null: false, comment: "Moss dimension id (API field `id`); fixed for cost centers and cost carriers"
      organisation_column(t)
      t.string :name, comment: "API field `name`"
      t.string :erp_name, comment: "API field `erpName`"
      t.string :erp_id, comment: "API field `erpId`"
      t.string :status, comment: "API field `status`: ACTIVE, DELETED, ..."
      t.string :items_table, comment: "Hitobito table holding the dimension's items (wsjrdp_cost_centers, wsjrdp_spheres); NULL = none"
      t.datetime :moss_created_at, comment: "API field `createTime`"
      t.datetime :moss_updated_at, comment: "API field `updateTime`"
      t.datetime :moss_deleted_at, comment: "API field `deleteTime`"
      sync_columns(t)
      t.timestamps
      t.index :moss_dimension_uuid, unique: true
    end

    add_column :wsjrdp_personal_accounts, :default_moss_team_uuid, :uuid,
      comment: "Moss team a new expense of the supplier goes to (Moss supplier API field `defaultTeamId`)"
    add_column :wsjrdp_personal_accounts, :default_moss_expense_account_uuid, :uuid,
      comment: "Supplier's default expense account (Moss supplier API field `defaultExpenseAccountId`)"
    add_column :wsjrdp_personal_accounts, :default_moss_cost_center_uuid, :uuid,
      comment: "Supplier's default cost center (Moss supplier API field `defaultCostCenterId`)"
    add_column :wsjrdp_personal_accounts, :default_moss_cost_carrier_uuid, :uuid,
      comment: "Supplier's default cost carrier, a sphere (Moss supplier API field `defaultCostCarrierId`)"
    %i[default_moss_team_uuid default_moss_expense_account_uuid default_moss_cost_center_uuid
      default_moss_cost_carrier_uuid].each do |column|
      add_index :wsjrdp_personal_accounts, column, where: "#{column} IS NOT NULL",
        name: "index_personal_accounts_on_#{column}"
    end

    MOSS_UUID_COMMENTS.each do |table, comment|
      add_column table, :moss_uuid, :uuid, comment: comment
      add_index table, :moss_uuid, unique: true, where: "moss_uuid IS NOT NULL"
    end

    # The supplier UUID was text so far, and never filled: now a real uuid,
    # unique like the other Moss ids.
    reversible do |dir|
      dir.up { change_column :wsjrdp_personal_accounts, :moss_uuid, :uuid, using: "NULLIF(moss_uuid, '')::uuid" }
      dir.down { change_column :wsjrdp_personal_accounts, :moss_uuid, :string }
    end
    add_index :wsjrdp_personal_accounts, :moss_uuid, unique: true, where: "moss_uuid IS NOT NULL"

    {
      wsjrdp_ledger_accounts: "Moss expense account",
      wsjrdp_personal_accounts: "Moss supplier",
      wsjrdp_cost_centers: "Moss dimension item",
      wsjrdp_spheres: "Moss dimension item"
    }.each do |table, source|
      add_column table, :moss_created_at, :datetime, comment: "#{source} field `createTime`"
      add_column table, :moss_updated_at, :datetime, comment: "#{source} field `updateTime`"
    end

    MOSS_STATUS_COMMENTS.each do |table, old_comment|
      add_column table, :moss_organisation_uuid, :uuid, default: MOSS_ORGANISATION_UUID,
        comment: "Moss organisation (API field `organisationId`)"
      change_column_comment table, :moss_status, from: old_comment,
        to: "Moss Status: active, deactivated or deleted; NULL = unknown to Moss (counts as deactivated)"
    end
  end

  private

  def organisation_column(t)
    t.uuid :moss_organisation_uuid, default: MOSS_ORGANISATION_UUID, comment: "API field `organisationId`"
  end

  def sync_columns(t)
    t.datetime :last_seen_at, comment: "Last sync that returned the row"
    t.datetime :moss_removed_at, comment: "Set when a sync no longer returned the row; cleared when it comes back"
    t.text :comment, null: false, default: "", comment: "Hitobito's own note on the row; the only field edited here"
    t.jsonb :additional_info, null: false, default: {}
  end
end
