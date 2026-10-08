# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# One file of a person: the row says where the file lies under the upload
# root (relative_storage_file_path) and where it lay when the row was written
# (absolute_storage_file_path), which version it is, what it refers to and who
# may read, write or delete it.
#
# - key, key_number, secondary_key, secondary_key_number: the kind of the
#   document and which of several it is (0 where there is one). Together with
#   derived_from_id and derivation_key they name a slot that holds at most one
#   current document (index_wsjrdp_documents_current).
# - key_ref, secondary_key_ref: free references to what the keys stand for,
#   e.g. a deregistration or a payment.
# - status: current, superseded or deleted. A newer document points at the
#   one it follows (replaces); superseded_at, deleted_at and replaces stay
#   when the status changes later on.
# - derived_from, derivation_key: a derivation (a preview, a PDF rendering)
#   carries the keys of its original and is deleted with it.
# - origin: ui, api or import; origin_service_token the API key of an upload
#   through the API.
# - readable_by, writable_by, deletable_by: who may read, write and delete;
#   one entry suffices. The entries are not checked here: one nobody knows
#   gives nobody access.
class WsjrdpDocument < ActiveRecord::Base
  CURRENT = "current"
  SUPERSEDED = "superseded"
  DELETED = "deleted"

  # None of the belongs_to has a dependent: deleting a document leaves the
  # person, the author, the references, the predecessor, the original and the
  # API key alone.
  belongs_to :subject, polymorphic: true
  belongs_to :author, polymorphic: true, optional: true
  belongs_to :key_ref, polymorphic: true, optional: true
  belongs_to :secondary_key_ref, polymorphic: true, optional: true
  belongs_to :replaces, class_name: "WsjrdpDocument", optional: true, inverse_of: :replaced_by
  belongs_to :derived_from, class_name: "WsjrdpDocument", optional: true, inverse_of: :derivatives
  belongs_to :origin_service_token, class_name: "ServiceToken", optional: true

  # The foreign keys do the same in the database (on_delete nullify and
  # cascade), so a delete outside Rails ends alike.
  has_one :replaced_by, class_name: "WsjrdpDocument", foreign_key: :replaces_id,
    inverse_of: :replaces, dependent: :nullify
  has_many :derivatives, class_name: "WsjrdpDocument", foreign_key: :derived_from_id,
    inverse_of: :derived_from, dependent: :destroy

  scope :current, -> { where(status: CURRENT) }
  scope :superseded, -> { where(status: SUPERSEDED) }
  scope :visible, -> { where.not(status: DELETED) }
  scope :originals, -> { where(derived_from_id: nil) }

  # As the check constraints of the table.
  validates :key_number, :secondary_key_number, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  validates :derivation_key, presence: true, if: -> { derived_from_id.present? || derived_from.present? }
  validates :content_sha256, format: {with: /\A[0-9a-f]{64}\z/}, allow_nil: true
end
