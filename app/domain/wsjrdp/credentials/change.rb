# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Credentials
  # Changes an existing version of this instance's stage
  # (doc/wsjrdp/credentials.md, "The write paths"); gives a WriteResult.
  #
  #   Wsjrdp::Credentials::Change.call(record: row, values: {"client_secret" => "...", "scope" => ""},
  #     name: "key of June", expires_at: Time.utc(2027, 12, 1))
  #   Wsjrdp::Credentials::Change.call(record: row, revoked_at: Time.current) # nil takes it back
  #
  # Only what is given changes; a field given as nil or "" is removed. The
  # kind's rules are checked for the fields given only, so that a changed
  # registry never makes a version impossible to revoke or rename. A secret
  # field can be changed only while the version's key is the active one
  # (else key_not_active, key_missing or unknown_scheme). The row is read
  # again and locked.
  class Change
    # An attribute left out keeps its value.
    NOT_GIVEN = Object.new.freeze

    def self.call(**) = new(**).call

    def initialize(record:, values: nil, name: NOT_GIVEN, comment: NOT_GIVEN, valid_from: NOT_GIVEN,
      expires_at: NOT_GIVEN, revoked_at: NOT_GIVEN, keys: Keys.current, kinds: Kinds.current)
      unless record.is_a?(WsjrdpCredential) && record.persisted?
        raise ArgumentError, "the record is not a saved #{WsjrdpCredential.name}"
      end
      raise ArgumentError, "the values are not a hash" unless values.nil? || values.is_a?(Hash)

      @attributes = {name: name, comment: comment, valid_from: valid_from, expires_at: expires_at,
                     revoked_at: revoked_at}.reject { |_attribute, value| value.equal?(NOT_GIVEN) }
      WsjrdpCredential.check_instants!(**@attributes.except(:name, :comment))
      @id = record.id
      @values = (values || {}).to_h { |name, value| [Wsjrdp::Credentials.name_of(name), value] }
      @keys = keys
      @kinds = kinds
    end

    def call
      WsjrdpCredential.transaction do
        row = WsjrdpCredential.lock.find_by(id: @id)
        row ? change(row) : WriteResult.new(errors: [Kind::Problem.new("base", :not_found)])
      end
    end

    private

    def change(row)
      return WriteResult.new(errors: [Kind::Problem.new("stage", :other_stage)]) unless row.stage == @keys.stage

      kind = @kinds[row.kind]
      return WriteResult.new(errors: [Kind::Problem.new("kind", :unknown_kind)]) if kind.nil? && @values.any?
      # Fields cannot be written into a column that is not a hash; the
      # name, the comment and the window still can be changed.
      if @values.any? && !row.values_columns_hashes?
        return WriteResult.new(errors: WriteResult.malformed_columns(row))
      end

      # With an unknown kind, @values is empty from here on.
      field_errors = []
      planned = plan(row, kind, field_errors)
      warnings = check_result(row, kind, planned, field_errors)
      assign_attributes(row)
      write_fields(row, kind, planned) if field_errors.empty?
      row.valid?
      errors = WriteResult.problems_of(row)
      return WriteResult.new(field_errors: field_errors, errors: errors, warnings: warnings) if (errors + field_errors).any?

      row.save!
      WriteResult.new(record: row, warnings: warnings)
    end

    # {name => cast value, or nil to remove}.
    def plan(row, kind, field_errors)
      key_problem = row.secret_key_problem(@keys)
      @values.each_with_object({}) do |(name, raw), planned|
        field = kind.field(name)
        next field_errors << Kind::Problem.new(Wsjrdp::Credentials.shown_name(name), :unknown) unless field
        next field_errors << Kind::Problem.new(name, key_problem) if field.secret? && key_problem
        next planned[name] = nil if raw.nil? || raw == ""

        value, code = field.cast(raw)
        code ? field_errors << Kind::Problem.new(name, code) : planned[name] = value
      end
    end

    # The kind's rules for the fields given only (in practice: a required
    # field removed); gives their warnings.
    def check_result(row, kind, planned, field_errors)
      return [] if planned.empty?

      cast = kind.cast(planned.compact, stage: row.stage)
      named = field_errors.map(&:field)
      cast.errors.each do |problem|
        next unless planned.key?(problem.field) && !named.include?(problem.field)

        field_errors << problem
      end
      cast.warnings.select { |problem| planned.key?(problem.field) }
    end

    def assign_attributes(row)
      @attributes.each do |attribute, value|
        value = nil if attribute == :name && value == ""
        row.public_send(:"#{attribute}=", value)
      end
    end

    def write_fields(row, kind, planned)
      return if planned.empty?

      key = @keys.find_by_fingerprint(row.encryption_key_fingerprint)
      current = row.readable_values(key).first
      planned.each do |name, value|
        field = kind.field(name)
        next if unchanged?(row, field, current, value)

        row.write_field(name, value, secret: field.secret?, key: key)
      end
    end

    def unchanged?(row, field, current, value)
      name = field.name
      return !row.sealed?(name) && !row.plain?(name) if value.nil?

      row.in_place?(name, secret: field.secret?) && current.key?(name) && current[name] == value
    end
  end
end
