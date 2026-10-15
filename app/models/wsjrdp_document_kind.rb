# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A kind of document (doc/wsjrdp/documents.md, "Document kinds"): per subject
# type and (key, secondary_key) -- matching a document's keys exactly --
#
# - readable_by, writable_by, deletable_by: the rights a new document of the
#   kind gets (Wsjrdp2027::DocumentStore copies them; later changes reach only
#   new documents);
# - content_types, extensions, max_upload_size_mb: what an upload of the kind
#   accepts (#upload_error); NULL means no restriction of its own, and when
#   both lists are set both must match;
# - people_column_name: the column of people that holds the path of the
#   kind's upload (upload_*_pdf, generated_registration_pdf), nil for a kind
#   without one; one kind per column;
# - role_rules: per contingent role of the person (Person#short_payment_role)
#   the first matching rule says whether the kind is offered for upload and to
#   whom, in which statuses not, whether it is required and which tag marks it
#   missing (#rule_for, #offered?, #required_for?, #missing_tag_for).
#
# A rule is a Hash of these keys, all optional:
#
#   roles           ["YP", "UL", ...]; absent: every role
#   offer_to        access entries of who may pick the kind (as in the rights
#                   lists, Wsjrdp2027::DocumentAccess); absent or []: not offered
#   not_for_status  statuses of the person in which it is not offered
#   required        true: the person must have it
#   missing_tag     {"tag" => ..., "from_status" => [...], "remove_on_upload" => bool}:
#                   the tag marks the document missing from these statuses on
class WsjrdpDocumentKind < ActiveRecord::Base
  # An access entry (person, log, finance_audit, ...): formed like a key
  # (Wsjrdp2027::DocumentFilename::KEY_PATTERN), at most ENTRY_MAX_LENGTH
  # characters. ENTRY_JS_PATTERN is the same for a JavaScript RegExp.
  ENTRY_MAX_LENGTH = 30
  ENTRY_FORMAT = /\A(?=.{1,#{ENTRY_MAX_LENGTH}}\z)#{Wsjrdp2027::DocumentFilename::KEY_PATTERN}\z/
  ENTRY_JS_PATTERN = "^(?=.{1,#{ENTRY_MAX_LENGTH}}$)#{Wsjrdp2027::DocumentFilename::KEY_PATTERN}$"
  CONTENT_TYPE_FORMAT = %r{\A[a-z0-9][a-z0-9.+-]*/(?:\*|[a-z0-9][a-z0-9.+-]*)\z}
  EXTENSION_FORMAT = /\A[a-z0-9]+(?:\.[a-z0-9]+)*\z/
  RULE_KEYS = %w[roles offer_to not_for_status required missing_tag].freeze
  MISSING_TAG_KEYS = %w[tag from_status remove_on_upload].freeze
  LISTS = %i[readable_by writable_by deletable_by].freeze

  scope :ordered, -> { order(:position, :key, :secondary_key) }

  validates :key, :label, :subject_type, presence: true
  validates :subject_type, inclusion: {in: ->(_) { Wsjrdp2027::DocumentSubjects.types }}
  validates :key, uniqueness: {scope: [:subject_type, :secondary_key]}
  validates :max_upload_size_mb, numericality: {only_integer: true, greater_than: 0}, allow_nil: true
  validates :people_column_name, uniqueness: true, allow_nil: true
  validate :people_column_valid

  normalizes :people_column_name, with: ->(name) { name.to_s.strip.presence }
  validate :keys_valid
  validate :entries_valid
  validate :files_valid
  validate :role_rules_valid

  # The kind of a document's keys, nil when there is none.
  def self.for(subject_type:, key:, secondary_key: "")
    find_by(subject_type: subject_type.to_s, key: key.to_s, secondary_key: secondary_key.to_s)
  end

  def self.for_document(document)
    self.for(subject_type: document.subject_type, key: document.key, secondary_key: document.secondary_key)
  end

  def self.statuses = Settings.status.to_h.keys.map(&:to_s)

  def self.roles = Wsjrdp2027::Person::SHORT_PAYMENT_ROLES.values

  # The columns of people that can hold the path of an upload.
  def self.people_columns = ::Person.column_names.grep(/_pdf\z/).sort

  # The rights a new document of the kind gets.
  def rights = LISTS.index_with { |list| Array(public_send(list)) }

  def to_s = label

  # The first rule for the person's contingent role, nil when none matches.
  def rule_for(person)
    role = person.short_payment_role
    Array(role_rules).find { |rule| rule["roles"].nil? || Array(rule["roles"]).include?(role) }
  end

  # Whether the kind is offered for upload for the person to the viewer
  # whose rights are ability (Wsjrdp2027::DocumentAccess#meets_entry?).
  def offered?(person, ability:)
    rule = rule_for(person)
    return false if rule.nil? || Array(rule["offer_to"]).empty?
    return false if Array(rule["not_for_status"]).include?(person.status.to_s)

    access = Wsjrdp2027::DocumentAccess.new(ability)
    access.admin? || Array(rule["offer_to"]).any? { |entry| access.meets_entry?(entry, subject_type, person) }
  end

  def required_for?(person) = rule_for(person)&.dig("required") == true

  # {"tag", "from_status", "remove_on_upload"} for the person, nil when the
  # rule has none.
  def missing_tag_for(person) = rule_for(person)&.dig("missing_tag")

  # Why an upload of the kind is refused (a message key and its
  # interpolations), nil when it is accepted.
  def upload_error(content_type:, filename:, byte_size:)
    if content_types.present? && content_types.none? { |pattern| content_type_matches?(pattern, content_type) }
      [:content_type, {types: content_types.join(", ")}]
    elsif extensions.present? && extensions.none? { |ext| filename.to_s.downcase.end_with?(".#{ext}") }
      [:extension, {extensions: extensions.join(", ")}]
    elsif max_upload_size_mb && byte_size.to_i > max_upload_size_mb.megabytes
      [:too_large, {size: max_upload_size_mb}]
    end
  end

  private

  def content_type_matches?(pattern, content_type)
    type = content_type.to_s.split(";").first.to_s.strip.downcase
    return type.start_with?(pattern.delete_suffix("*")) if pattern.end_with?("/*")

    type == pattern
  end

  def people_column_valid
    return if people_column_name.nil?
    return errors.add(:people_column_name, :not_for_subject) unless subject_type == "Person"

    errors.add(:people_column_name, :unknown_column) unless self.class.people_columns.include?(people_column_name)
  end

  def keys_valid
    error = Wsjrdp2027::DocumentFilename.key_error(key)
    errors.add(:key, :"key_#{error}") if key.present? && error
    return if secondary_key.blank?

    error = Wsjrdp2027::DocumentFilename.key_error(secondary_key)
    errors.add(:secondary_key, :"key_#{error}") if error
  end

  def entries_valid
    LISTS.each do |list|
      bad = Array(public_send(list)).reject { |entry| entry.to_s.match?(ENTRY_FORMAT) }
      errors.add(list, :invalid_entries, entries: bad.join(", ")) if bad.any?
    end
  end

  def files_valid
    bad = Array(content_types).reject { |type| type.to_s.match?(CONTENT_TYPE_FORMAT) }
    errors.add(:content_types, :invalid_entries, entries: bad.join(", ")) if bad.any?
    bad = Array(extensions).reject { |ext| ext.to_s.match?(EXTENSION_FORMAT) }
    errors.add(:extensions, :invalid_entries, entries: bad.join(", ")) if bad.any?
  end

  def role_rules_valid
    return errors.add(:role_rules, :not_a_list) unless role_rules.is_a?(Array)

    role_rules.each_with_index do |rule, index|
      problem = rule_problem(rule)
      errors.add(:role_rules, :invalid_rule, number: index + 1, problem: problem) if problem
    end
  end

  # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
  def rule_problem(rule)
    return "keine Regel" unless rule.is_a?(Hash)

    unknown = rule.keys - RULE_KEYS
    return "unbekannte Schlüssel #{unknown.join(", ")}" if unknown.any?
    return "Rollen #{(Array(rule["roles"]) - self.class.roles).join(", ")}" if rule.key?("roles") &&
      (!rule["roles"].is_a?(Array) || (rule["roles"] - self.class.roles).any?)
    return "offer_to" if rule.key?("offer_to") &&
      (!rule["offer_to"].is_a?(Array) || rule["offer_to"].any? { |entry| !entry.to_s.match?(ENTRY_FORMAT) })
    return "not_for_status" if rule.key?("not_for_status") && !statuses?(rule["not_for_status"])
    return "required" if rule.key?("required") && ![true, false].include?(rule["required"])

    missing_tag_problem(rule["missing_tag"]) if rule.key?("missing_tag")
  end
  # rubocop:enable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity

  def missing_tag_problem(tag)
    return "missing_tag" unless tag.is_a?(Hash) && (tag.keys - MISSING_TAG_KEYS).empty?
    return "missing_tag.tag" if tag["tag"].to_s.strip.empty?
    return "missing_tag.from_status" unless optional(tag, "from_status") { |list| statuses?(list) }

    "missing_tag.remove_on_upload" unless optional(tag, "remove_on_upload") { |value| [true, false].include?(value) }
  end

  # Whether hash lacks key or its value passes the block.
  def optional(hash, key) = !hash.key?(key) || yield(hash[key])

  def statuses?(list) = list.is_a?(Array) && (list.map(&:to_s) - self.class.statuses).empty?
end
