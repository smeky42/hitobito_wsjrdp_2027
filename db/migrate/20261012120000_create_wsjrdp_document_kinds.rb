# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class CreateWsjrdpDocumentKinds < ActiveRecord::Migration[7.1]
  ALL_ROLES_PDF = {content_types: %w[application/pdf], extensions: %w[pdf]}.freeze
  NOT_REGISTERED = %w[registered].freeze
  OFFER = {"offer_to" => %w[update], "not_for_status" => NOT_REGISTERED}.freeze

  KINDS = [
    {key: "contract", label: "Vertrag (Anmeldung)", position: 10, people_column_name: "upload_contract_pdf",
     readable_by: %w[person update finance_audit], role_rules: [OFFER.merge("required" => true)]},
    {key: "sepa", label: "SEPA-Mandat", position: 20, people_column_name: "upload_sepa_pdf",
     readable_by: %w[person update finance_audit], role_rules: [OFFER.merge("required" => true)]},
    {key: "medical", label: "Medizinbogen", position: 30, people_column_name: "upload_medical_pdf",
     role_rules: [OFFER.merge("required" => true)]},
    {key: "photo_permission", label: "Fotoeinwilligung", position: 40, people_column_name: "upload_photo_permission_pdf",
     role_rules: [OFFER.merge("required" => true)]},
    {key: "passport", label: "Ausweisdokument", position: 50, people_column_name: "upload_passport_pdf",
     role_rules: [OFFER.merge("required" => true)]},
    {key: "data_agreement", label: "Vertraulichkeitsvereinbarung", position: 60,
     people_column_name: "upload_data_agreement_pdf",
     role_rules: [OFFER.merge("roles" => %w[UL CMT], "required" => true)]},
    {key: "recommendation", label: "Empfehlungsschreiben", position: 70,
     people_column_name: "upload_recommendation_pdf",
     role_rules: [OFFER.merge("roles" => %w[UL], "required" => true)]},
    {key: "good_conduct", label: "Nachweis über ein Führungszeugnis", position: 80,
     people_column_name: "upload_good_conduct_pdf",
     role_rules: [
       OFFER.merge("roles" => %w[UL CMT], "required" => true,
         "missing_tag" => {"tag" => "eFZ-Einsicht-fehlt", "from_status" => %w[in_review reviewed confirmed]}),
       OFFER.merge("roles" => %w[IST], "required" => false,
         "missing_tag" => {"tag" => "eFZ-Einsicht-fehlt", "from_status" => %w[in_review reviewed confirmed]})
     ]},
    {key: "registration-generated", label: "Anmeldung (erzeugt)", position: 90,
     people_column_name: "generated_registration_pdf", writable_by: [], role_rules: []}
  ].freeze

  def change
    create_table :wsjrdp_document_kinds do |t|
      t.string :subject_type, null: false, default: "Person"
      t.string :key, null: false
      # "" for documents without one; matches wsjrdp_documents.secondary_key
      # exactly.
      t.string :secondary_key, null: false, default: ""
      t.string :label, null: false
      t.text :description, null: false, default: ""
      # Copied into a new document of the kind.
      t.string :readable_by, array: true, null: false, default: []
      t.string :writable_by, array: true, null: false, default: []
      t.string :deletable_by, array: true, null: false, default: []
      # NULL: no restriction of its own; both set: both must match.
      t.string :content_types, array: true, null: true
      t.string :extensions, array: true, null: true
      t.integer :max_upload_size_mb, null: true
      # Per contingent role, the first matching rule applies: roles, offer_to,
      # not_for_status, required, missing_tag (WsjrdpDocumentKind).
      t.jsonb :role_rules, null: false, default: []
      t.integer :position, null: false, default: 0
      # The column of people that holds the path of the kind's upload
      # (people.upload_*_pdf, generated_registration_pdf); NULL for a kind
      # without one.
      t.string :people_column_name, null: true
      t.jsonb :additional_info, null: false, default: {}
      t.timestamps null: false
    end
    add_index :wsjrdp_document_kinds, [:subject_type, :key, :secondary_key], unique: true,
      name: "index_wsjrdp_document_kinds_on_subject_and_keys"
    add_index :wsjrdp_document_kinds, :people_column_name, unique: true, where: "people_column_name IS NOT NULL",
      name: "index_wsjrdp_document_kinds_on_people_column_name"
    add_check_constraint :wsjrdp_document_kinds, "max_upload_size_mb IS NULL OR max_upload_size_mb > 0",
      name: "chk_wsjrdp_document_kinds_max_upload_size_mb"

    reversible do |direction|
      direction.up { insert_registration_kinds }
    end
  end

  private

  def insert_registration_kinds
    now = Time.current
    KINDS.each do |kind|
      row = {readable_by: %w[person update], writable_by: %w[log], deletable_by: %w[log]}
        .merge(ALL_ROLES_PDF).merge(kind).merge(created_at: now, updated_at: now)
      execute(<<~SQL)
        INSERT INTO wsjrdp_document_kinds
          (subject_type, key, secondary_key, label, readable_by, writable_by, deletable_by,
           content_types, extensions, role_rules, position, people_column_name, created_at, updated_at)
        VALUES ('Person', #{quote(row[:key])}, '', #{quote(row[:label])},
          #{array(row[:readable_by])}, #{array(row[:writable_by])}, #{array(row[:deletable_by])},
          #{array(row[:content_types])}, #{array(row[:extensions])},
          #{quote(row[:role_rules].to_json)}::jsonb, #{row[:position].to_i}, #{quote(row[:people_column_name])},
          #{quote(now)}, #{quote(now)})
      SQL
    end
  end

  def quote(value) = connection.quote(value)

  def array(values) = "ARRAY[#{values.map { |value| quote(value) }.join(", ")}]::varchar[]"
end
