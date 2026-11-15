# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# One row of a person's deregistration: a withdrawal, a termination or a
# cancellation of the registration, with its dates, the compensation and the
# form. number counts the rows of a person, a replacing row included.
#
# The row is written down in steps (STATUSES) and fixed in two:
#
# - From form_sent on, what the sent form says stays: kind, issue, the dates,
#   the deadline, the entered compensation, show_contractual_compensation,
#   form_options, form_sent_at, form_snapshot and the sent form
#   (sent_form_document_id). Changing one of them means a new row
#   (#new_version!): the old one becomes superseded, the new one points at it
#   (replaces) and gets the next number.
# - A row in a final status (FINAL_STATUSES, closed_at set) is done.
#
# signed_form_document_id points at the form that came back signed,
# signed_form_received_at says when it came in.
# comment and additional_info stay changeable. Every change is written down
# as a WsjrdpDeregistrationEvent, and reaches the person log through
# PaperTrail.
#
# What the made form captured (FORM_SNAPSHOT_KEYS) lives in form_snapshot, what
# the Moss refund receipt carries (RECEIPT_KEYS) in
# additional_info["refund_receipt"] -- the receipt is made after the form went
# out, so it stays changeable. The person reads and writes all of it through
# its deregistration_* accessors (Wsjrdp2027::Person), on the person's current
# row (#current_for). doc/wsjrdp/deregistration.md has the whole picture.
class WsjrdpDeregistration < ActiveRecord::Base
  STATUSES = %w[
    recorded form_created form_sent signed_form_received refund_initiated refund_booked
    confirmation_sent finished canceled superseded deleted
  ].freeze
  FINAL_STATUSES = %w[finished canceled superseded deleted].freeze
  KINDS = %w[withdrawal termination cancellation].freeze
  DEFAULT_KIND = "withdrawal"
  # What the sent form says; fixed from form_sent on.
  FIXED_ATTRS = %w[
    kind issue requested_date effective_date reply_due_date actual_compensation
    actual_compensation_currency show_contractual_compensation form_options
    form_sent_at form_snapshot sent_form_document_id
  ].freeze
  # What a new version takes over from the row it replaces: what was entered,
  # not what the made form captured.
  CARRIED_ATTRS = %w[
    kind issue requested_date effective_date reply_due_date actual_compensation
    actual_compensation_currency show_contractual_compensation comment
  ].freeze
  # The keys of form_snapshot: the made form's day and deadline, and the
  # person's bank data, role and team or unit as they stood then.
  FORM_SNAPSHOT_KEYS = %w[
    created_date effective_reply_due_date
    refund_account_holder refund_iban refund_bic refund_sepa_address
    person_role person_role_name person_team_unit
  ].freeze
  RECEIPT_KEY = "refund_receipt"
  # The keys of additional_info["refund_receipt"].
  RECEIPT_KEYS = %w[created_date created_by_id snapshot text show_default_explanation].freeze
  # The event a sent form is written down as (Wsjrdp2027::DeregistrationFormSent).
  FORM_SENT_ACTION = "form_sent"

  belongs_to :person, class_name: "::Person", optional: true, inverse_of: :wsjrdp_deregistrations
  belongs_to :replaces, class_name: "WsjrdpDeregistration", optional: true
  belongs_to :sent_form_document, class_name: "WsjrdpDocument", optional: true
  belongs_to :signed_form_document, class_name: "WsjrdpDocument", optional: true
  has_many :events, -> { order(:occurred_at, :id) }, class_name: "WsjrdpDeregistrationEvent",
    foreign_key: :deregistration_id, inverse_of: :deregistration, dependent: :delete_all

  has_paper_trail meta: {main_id: ->(row) { row.person_id }, main_type: ->(_row) { ::Person.sti_name }},
    skip: %w[updated_at]

  validates :number, numericality: {only_integer: true, greater_than_or_equal_to: 1}
  validates :status, inclusion: {in: STATUSES}
  validates :kind, inclusion: {in: KINDS}
  validate :one_open_per_person, unless: :final?
  validate :fixed_values_unchanged

  before_save :close_when_final
  after_create { write_event("create") }
  after_update { write_event("update") if saved_changes.except("updated_at").any? }

  class << self
    # The row the person's accessors work on: the open one, else the latest.
    # Read from the loaded rows, so a row built but not yet saved counts.
    def current_for(rows)
      rows = rows.reject(&:marked_for_destruction?)
      rows.find { |row| !row.final? } || rows.max_by(&:number)
    end

    # The actor of what is written now: who PaperTrail names for the request
    # (a person, or an API key -- whodunnit_type), nobody in a console.
    def current_actor
      id = ::PaperTrail.request.whodunnit
      return [nil, nil] if id.blank?

      type = ::PaperTrail.request.controller_info.to_h[:whodunnit_type].presence || ::Person.sti_name
      [type, id.to_i]
    end
  end

  def final? = FINAL_STATUSES.include?(status)

  # Whether what the form says may still change: not once it went out, not
  # once the row is done.
  def fixed? = form_sent_at_in_database.present? || FINAL_STATUSES.include?(status_in_database.to_s)

  def editable? = !fixed?

  def kind_or_default = kind.presence || DEFAULT_KIND

  def actual_compensation_cents = actual_compensation && (actual_compensation * 100).round

  def actual_compensation_cents=(cents)
    self.actual_compensation = cents.nil? ? nil : BigDecimal(cents.to_i) / 100
  end

  def snapshot_value(key) = form_snapshot.to_h[key.to_s]

  # One value of form_snapshot; blank removes the key. A copy is written, so
  # the change is seen.
  def write_snapshot_value(key, value)
    self.form_snapshot = with_value(form_snapshot, key, value)
  end

  def receipt = additional_info.to_h[RECEIPT_KEY].to_h

  def receipt_value(key) = receipt[key.to_s]

  def write_receipt_value(key, value)
    receipt = with_value(self.receipt, key, value)
    info = additional_info.to_h.except(RECEIPT_KEY)
    info[RECEIPT_KEY] = receipt if receipt.present?
    self.additional_info = info
  end

  # The mails the form went out with, oldest first: what each form_sent event
  # recorded (Wsjrdp2027::DeregistrationFormSent).
  def form_mailings
    events.select { |event| event.event == "notify" && event.action == FORM_SENT_ACTION }
      .map { |event| event.additional_info.to_h }
  end

  # The next version of a row that is fixed: a new open row with what was
  # entered, pointing at this one, which becomes superseded. Answers the new
  # row; both are saved.
  def new_version!
    raise ActiveRecord::RecordInvalid, self if final?

    replacement = self.class.new(attributes.slice(*CARRIED_ATTRS).merge(
      person_id: person_id, number: self.class.where(person_id: person_id).maximum(:number).to_i + 1,
      replaces_id: id, status: "recorded"
    ))
    transaction do
      update!(status: "superseded")
      replacement.save!
    end
    replacement
  end

  private

  def with_value(hash, key, value)
    copy = hash.to_h.dup
    value = value.iso8601 if value.respond_to?(:iso8601) && value.is_a?(Date)
    if value.nil? || value == "" || value == {}
      copy.delete(key.to_s)
    else
      copy[key.to_s] = value
    end
    copy
  end

  # A person has at most one deregistration row that is not in a final
  # status; a replacing row comes after the old one became superseded.
  def one_open_per_person
    others = self.class.where(person_id: person_id).where.not(status: FINAL_STATUSES)
    others = others.where.not(id: id) if persisted?
    errors.add(:status, :taken) if others.exists?
  end

  # What the sent form says stays, and a row that is done stays done.
  def fixed_values_unchanged
    return unless persisted? && fixed?

    changed_fixed = changed & FIXED_ATTRS
    changed_fixed -= %w[form_sent_at sent_form_document_id] if form_sent_at_in_database.nil?
    errors.add(:base, :deregistration_fixed) if changed_fixed.any?
  end

  def close_when_final
    self.closed_at ||= Time.current if final?
  end

  def write_event(event)
    actor_type, actor_id = self.class.current_actor
    from, to = saved_changes["status"]
    WsjrdpDeregistrationEvent.create!(
      deregistration_id: id, event: event, actor_type: actor_type, actor_id: actor_id,
      action: (to if saved_changes.key?("status")),
      from_status: (from if saved_changes.key?("status") && event == "update"),
      to_status: (to if saved_changes.key?("status")) || ((event == "create") ? status : nil),
      field_changes: saved_changes.except("updated_at", "created_at", "id").as_json
    )
  end
end
