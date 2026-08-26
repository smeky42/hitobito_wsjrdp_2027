# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Filtering
  # How operand(s) become a predicate, plus UI metadata. `arity` tells the UI
  # (and the compiler) how many operands to expect:
  # :none | :one | :two (range) | :many (set).
  #
  # The key MUST be in OPERATOR_VOCABULARY, and the short_key always comes from
  # there (never passed per instance), so key/short_key stay globally
  # consistent. The same key may be implemented by several types (gte on
  # decimal and on date differ only in label and operand casting): that is one
  # operator concept with per-type implementations, not a collision.
  #
  # Optional metadata:
  # label_many: chip/display label when there is more than one operand
  #   ("ist eines von") -- makes the ANY-of semantics of a multi-select visible.
  # many_hint: editor hint shown while several values are selected.
  # case_group/case_sensitive: case-insensitive/-sensitive operator pairs share
  #   a case_group; the UI lists the group once (its insensitive member) and
  #   offers a separate "Groß-/Kleinschreibung" toggle (insensitive = default).
  # operand_control: overrides the attribute's control for THIS operator's
  #   operand input (e.g. "year" / "month" on a date attribute).
  # cast: per-operator operand cast (proc value -> cast value or nil for
  #   invalid), overriding the type's cast (e.g. year number on a date column,
  #   regex validation).
  class Operator
    attr_reader :key, :short_key, :label, :arity, :label_many, :many_hint,
      :case_group, :case_sensitive, :operand_control, :cast

    def initialize(key:, label:, arity:, label_many: nil, many_hint: nil,
      case_group: nil, case_sensitive: nil, operand_control: nil, cast: nil,
      &to_arel)
      @key = key
      @short_key = OPERATOR_VOCABULARY.fetch(key) # raises on unregistered key
      @label = label
      @arity = arity
      @label_many = label_many
      @many_hint = many_hint
      @case_group = case_group
      @case_sensitive = case_sensitive
      @operand_control = operand_control
      @cast = cast
      @to_arel = to_arel
    end

    # column: an Arel attribute / expression (or an array of them for
    # multi-column types); operands: cast, validated values.
    def to_arel(column, operands)
      @to_arel.call(column, operands)
    end

    def arity_satisfied?(operands)
      case arity
      when :none then operands.empty?
      when :one then operands.size == 1
      when :two then operands.size == 2
      when :many then operands.any?
      else false
      end
    end

    def as_json(*)
      {key: key, label: label, arity: arity, label_many: label_many,
       many_hint: many_hint, case_group: case_group,
       case_sensitive: case_sensitive, operand_control: operand_control}
    end
  end
end
