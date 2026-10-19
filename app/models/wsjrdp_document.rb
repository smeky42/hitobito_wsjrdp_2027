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
# - file_status: present or missing, whether the file exists (apart from
#   status); file_checked_at when that was last found out. A missing file
#   keeps its row and its name; its byte_size may be unknown.
# - readable_by, writable_by, deletable_by: who may read, write and delete;
#   access is granted if one entry matches (Wsjrdp2027::DocumentAccess).
#   Invalid or unknown entries are ignored.
#
# The keys are checked as the file name needs them
# (Wsjrdp2027::DocumentFilename.key_error); Wsjrdp2027::DocumentStore writes
# the file and the row, doc/wsjrdp/documents.md describes both.
class WsjrdpDocument < ActiveRecord::Base
  CURRENT = "current"
  SUPERSEDED = "superseded"
  DELETED = "deleted"
  FILE_PRESENT = "present"
  FILE_MISSING = "missing"
  FILE_STATUSES = [FILE_PRESENT, FILE_MISSING].freeze

  # None of the belongs_to has a dependent: deleting a document leaves the
  # person, the author, the references, the predecessor, the original and the
  # API key alone. The person is needed to make a document; the documents of
  # a deleted person keep pointing at it and stay changeable.
  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :author, polymorphic: true, optional: true
  belongs_to :key_ref, polymorphic: true, optional: true
  belongs_to :secondary_key_ref, polymorphic: true, optional: true
  belongs_to :replaces, class_name: "WsjrdpDocument", optional: true, inverse_of: :replacements
  belongs_to :derived_from, class_name: "WsjrdpDocument", optional: true, inverse_of: :derivatives
  belongs_to :origin_service_token, class_name: "ServiceToken", optional: true

  # The foreign keys do the same in the database (on_delete nullify and
  # cascade), so a delete outside Rails ends alike.
  # A document may be followed by several, e.g. when one scan is split up.
  has_many :replacements, class_name: "WsjrdpDocument", foreign_key: :replaces_id,
    inverse_of: :replaces, dependent: :nullify
  has_many :derivatives, class_name: "WsjrdpDocument", foreign_key: :derived_from_id,
    inverse_of: :derived_from, dependent: :destroy

  scope :current, -> { where(status: CURRENT) }
  scope :superseded, -> { where(status: SUPERSEDED) }
  scope :visible, -> { where.not(status: DELETED) }
  scope :originals, -> { where(derived_from_id: nil) }
  scope :file_missing, -> { where(file_status: FILE_MISSING) }

  # The documents of one subject, of one slot (the keys of an original).
  scope :of_subject, ->(subject) { where(subject_type: subject.class.base_class.name, subject_id: subject.id) }
  scope :in_slot, ->(key:, key_number: 0, secondary_key: "", secondary_key_number: 0) {
    where(key: key, key_number: key_number, secondary_key: secondary_key, secondary_key_number: secondary_key_number)
  }

  validates :subject, presence: true, on: :create
  validates :subject_type, inclusion: {in: ->(_) { Wsjrdp2027::DocumentSubjects.types }}, on: :create
  validates :filename, presence: true
  validate :keys_valid, on: :create
  # Every new document, whatever writes it, keeps a name UploadFilename lets
  # through, normalized (DocumentStore takes a name as given that way).
  validate :filename_valid, on: :create, if: -> { filename.present? }
  validate :slot_free, on: :create, if: -> { status == CURRENT }

  # As the check constraints of the table.
  validates :key_number, :secondary_key_number, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  validates :derivation_key, presence: true, if: -> { derived_from_id.present? || derived_from.present? }
  validates :content_sha256, format: {with: /\A[0-9a-f]{64}\z/}, allow_nil: true
  validates :file_status, inclusion: {in: FILE_STATUSES}
  validates :byte_size, presence: true, unless: :file_missing?

  # The current original of a subject in a slot, nil when there is none.
  def self.current_for(subject, **slot)
    of_subject(subject).current.originals.in_slot(**slot).first
  end

  # Sets file_checked_at of the rows to at, leaving out a row someone is
  # writing at that moment (SKIP LOCKED; the writer stamps it): the
  # statement never waits, so it cannot wait in a circle with a writer that
  # holds several rows (doc/wsjrdp/locked_change.md). Answers how many rows
  # it stamped.
  def self.stamp_checked(ids, at)
    free = where(id: ids).lock("FOR NO KEY UPDATE SKIP LOCKED").select(:id)
    where(id: free).update_all(file_checked_at: at)
  end

  # The documents this one follows, oldest first.
  def predecessors
    chain = []
    document = replaces
    while document && chain.exclude?(document)
      chain.unshift(document)
      document = document.replaces
    end
    chain
  end

  def current? = status == CURRENT

  def file_missing? = file_status == FILE_MISSING

  private

  def keys_valid
    key_errors = {key: key}
    key_errors[:secondary_key] = secondary_key if secondary_key.to_s != ""
    key_errors[:derivation_key] = derivation_key unless derivation_key.nil?
    key_errors.each do |attribute, value|
      error = Wsjrdp2027::DocumentFilename.key_error(value)
      errors.add(attribute, :"key_#{error}") if error
    end
  end

  def filename_valid
    problem = Wsjrdp2027::UploadFilename.problem(filename)
    return unless problem

    errors.add(:filename, problem, **Wsjrdp2027::UploadFilename.error_options(filename))
  end

  # One current document per slot (index_wsjrdp_documents_current); the one
  # this document replaces gives up its place as it is saved.
  def slot_free
    taken = WsjrdpDocument.current
      .where(subject_type: subject_type, subject_id: subject_id, derived_from_id: derived_from_id,
        derivation_key: derivation_key)
      .in_slot(key: key, key_number: key_number, secondary_key: secondary_key,
        secondary_key_number: secondary_key_number)
      .where.not(id: [id, replaces_id].compact)
    errors.add(:base, :slot_taken) if taken.exists?
  end
end
