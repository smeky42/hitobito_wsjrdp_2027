# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Credentials
  # Re-keys a version of this instance's stage (doc/wsjrdp/credentials.md,
  # "The write paths"); gives a WriteResult.
  #
  #   Wsjrdp::Credentials::Rekey.call(record: row)
  #
  # Every sealed value is sealed again with the active key, and every field
  # moves into the column the kind names now. All or nothing: a value that
  # does not open with the version's key, or a value column that is not a
  # hash, changes nothing. With the active key already, only misplaced
  # fields move (warning already_active). The row is read again and locked.
  class Rekey
    def self.call(**) = new(**).call

    def initialize(record:, keys: Keys.current, kinds: Kinds.current)
      unless record.is_a?(WsjrdpCredential) && record.persisted?
        raise ArgumentError, "the record is not a saved #{WsjrdpCredential.name}"
      end

      @id = record.id
      @keys = keys
      @kinds = kinds
    end

    def call
      active = @keys.active!
      WsjrdpCredential.transaction do
        row = WsjrdpCredential.lock.find_by(id: @id)
        row ? rekey(row, active) : failure("base", :not_found)
      end
    end

    private

    def rekey(row, active)
      return failure("stage", :other_stage) unless row.stage == @keys.stage
      return failure("scheme", :unknown_scheme) unless row.scheme == Sealer::SCHEME
      return WriteResult.new(errors: WriteResult.malformed_columns(row)) unless row.values_columns_hashes?

      version_key = @keys.find_by_fingerprint(row.encryption_key_fingerprint)
      return failure("encryption_key_fingerprint", :key_missing) unless version_key

      values, field_errors = readable_values(row, version_key)
      targets = targets(row, values)
      field_errors += unsealable(values, targets)
      return WriteResult.new(field_errors: field_errors) if field_errors.any?

      same_key = version_key.fingerprint == active.fingerprint
      write(row, active, values, targets, same_key)
      row.valid?
      errors = WriteResult.problems_of(row)
      return WriteResult.new(errors: errors) if errors.any?

      row.save!
      warnings = same_key ? [Kind::Problem.new("encryption_key_fingerprint", :already_active)] : []
      WriteResult.new(record: row, warnings: warnings)
    end

    def failure(attribute, code) = WriteResult.new(errors: [Kind::Problem.new(attribute, code)])

    def readable_values(row, version_key)
      values, failing = row.readable_values(version_key)
      [values, failing.map { |name| Kind::Problem.new(Wsjrdp::Credentials.shown_name(name), :not_opening) }]
    end

    # {name => whether to seal it}: by the kind, else where it lies.
    def targets(row, values)
      kind = @kinds[row.kind]
      values.keys.to_h do |name|
        field = kind&.field(name)
        [name, field ? field.secret? : row.sealed?(name)]
      end
    end

    def unsealable(values, targets)
      targets.filter_map do |name, secret|
        shown = Wsjrdp::Credentials.shown_name(name)
        next Kind::Problem.new(shown, :not_a_name) unless Wsjrdp::Credentials.name?(name)
        next unless secret && Sealer.value_problem(values[name])

        Kind::Problem.new(shown, :not_a_value)
      end
    end

    def write(row, active, values, targets, same_key)
      unless same_key
        row.encryption_key_fingerprint = active.fingerprint
        row.encryption_key_label = @keys.label
      end
      values.each do |name, value|
        secret = targets.fetch(name)
        # With the same key, a field in its place keeps its sealed text.
        next if same_key && row.in_place?(name, secret: secret)

        row.write_field(name, value, secret: secret, key: active)
      end
    end
  end
end
