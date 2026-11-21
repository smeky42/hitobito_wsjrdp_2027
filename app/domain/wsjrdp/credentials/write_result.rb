# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Credentials
  # What a write path (Deposit, Change, Rekey) gives back, as codes:
  # field_errors are the kind's fields, errors the version's attributes,
  # kept apart so that a field can never be taken for an attribute. A
  # warning never stops a write. Nothing shows a value.
  class WriteResult
    include Undumpable

    attr_reader :record, :field_errors, :errors, :warnings

    def self.problems_of(record)
      record.errors.map { |error| Kind::Problem.new(error.attribute.to_s, error.type) }
    end

    # not_field_values for each value column of the row that is not a hash.
    def self.malformed_columns(row)
      %w[public_data secret_data].reject { |column| row[column].is_a?(Hash) }
        .map { |column| Kind::Problem.new(column, :not_field_values) }
    end

    def initialize(record: nil, field_errors: [], errors: [], warnings: [])
      @record = record
      @field_errors = field_errors.dup.freeze
      @errors = errors.dup.freeze
      @warnings = warnings.dup.freeze
      freeze
    end

    def saved? = !record.nil?

    def inspect
      "#<#{self.class.name} record=#{record&.id.inspect} field_errors=#{field_errors.join(", ")} " \
        "errors=#{errors.join(", ")} warnings=#{warnings.join(", ")}>"
    end
    alias_method :to_s, :inspect

    def as_json(*)
      {"record_id" => record&.id, "field_errors" => field_errors.map(&:as_json), "errors" => errors.map(&:as_json),
       "warnings" => warnings.map(&:as_json)}
    end
  end
end
