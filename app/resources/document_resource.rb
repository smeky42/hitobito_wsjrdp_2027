# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The stored documents in the JSON:API, read only (GET /api/documents and
# /api/documents/:id; doc/wsjrdp/documents.md). An API key needs the scope
# people:documents and an acting person (Wsjrdp2027::TokenAbility).
#
# Who may read a document is its own list readable_by
# (Wsjrdp2027::DocumentAccess), which no SQL condition expresses; the list
# therefore needs filter[subject_id] and is checked document by document.
class DocumentResource < ApplicationResource
  primary_endpoint "documents", [:index, :show]
  self.model = WsjrdpDocument
  self.type = :documents

  with_options writable: false, filterable: false, sortable: false do
    attribute :subject_type, :string, filterable: true
    attribute :subject_id, :integer, filterable: true
    attribute :key, :string, filterable: true
    attribute :key_number, :integer
    attribute :secondary_key, :string
    attribute :secondary_key_number, :integer
    attribute :derived_from_id, :integer
    attribute :derivation_key, :string
    attribute :replaces_id, :integer
    attribute :status, :string, filterable: true
    attribute :filename, :string
    attribute :content_type, :string
    attribute :byte_size, :integer
    attribute :file_status, :string, filterable: true
    attribute :file_checked_at, :datetime
    attribute :content_sha256, :string
    attribute :document_date, :date
    attribute :comment, :string
    attribute :origin, :string
    attribute :created_at, :datetime, sortable: true
    attribute :updated_at, :datetime
  end

  def base_scope
    readable = candidates.to_a.select { |document| can?(:show, document) }
    WsjrdpDocument.where(id: readable.map(&:id))
  end

  # The subjects the list asks for, from filter[subject_id] ("1", "1,2" or
  # {eq: ...}).
  def self.subject_ids(params)
    value = params.dig(:filter, :subject_id)
    value = value[:eq] || value["eq"] if value.respond_to?(:key?)
    Array(value).flat_map { |part| part.to_s.split(",") }.map(&:strip).grep(/\A\d+\z/).map(&:to_i)
  end

  private

  def candidates
    params = context.request.params.with_indifferent_access
    if params[:id].present?
      WsjrdpDocument.where(id: params[:id])
    else
      WsjrdpDocument.where(subject_type: "Person", subject_id: self.class.subject_ids(params))
    end
  end
end
