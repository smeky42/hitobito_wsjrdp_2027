# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Filtering
  # One filterable attribute of a dataset.
  #
  # operators: REQUIRED -- the explicit list of operator keys this attribute
  #   ACCEPTS, resolved against the type's implementation library. Nothing is
  #   derived implicitly from the type; an unknown key raises at declaration
  #   time (host-authored, so fail loud). Accepting an operator is what the URL
  #   codec, fixed slots, presets, chips and the compiler go by.
  # pickable: the subset of `operators:` the EDITOR offers in its operator
  #   dropdown; defaults to all accepted ones. The difference is deliberate: an
  #   operator can stay valid in a hand-written URL, a fixed slot or a preset
  #   without cluttering the dropdown (e.g. `eq`/`gt`/`lt` next to the three
  #   amount operators a user should reach for). The catalog marks every
  #   operator `pickable: true/false`; the builder lists only the pickable ones
  #   -- plus, while editing, the condition's OWN operator, so a non-pickable
  #   chip can be re-saved unchanged.
  # short_key: short name used in the URL (Rison) encoding only; JSON tree and
  #   catalog always use the full key. Defaults to the key itself.
  # column: in a bound schema an Arel attribute / expression (or an array for
  #   multi-column types). In a TEMPLATE: a symbol (resolved as
  #   base.arel_table[sym] at bind time) or a lambda ->(t) { ... } receiving
  #   the arel_table (may return an array).
  # options: a Wsjrdp::Filtering::Options describing how the UI gets [value, label]
  #   pairs (only for reference/enum controls).
  # operand_min: lower bound for the editor's numeric operand inputs (the
  #   `min` attribute). Cosmetic guidance only -- an ABS() column cannot match a
  #   negative bound anyway, so the server does not re-validate it.
  # catalog: false = registered for compilation only, omitted from the catalog
  #   (so it can back a hidden condition without a UI control).
  # variant_group: several attributes may form ONE entry in the attribute
  #   picker (labelled with this string); the editor then offers the group
  #   members as sub-variants (e.g. the text search over Buchungstext /
  #   Belege / both, or an amount next to its absolute value). The first
  #   declared member is the group's default.
  # sign: :signed or :absolute -- marks the two members of an amount's sign
  #   pair (the signed column and its ABS() twin). The editor renders such a
  #   group as a ± / |x| toggle instead of the sub-variant dropdown; the
  #   pairing itself is checked at declaration time (Schema.define).
  class Attribute
    attr_reader :key, :short_key, :label, :group, :type, :column, :options,
      :variant_group, :operand_min, :sign

    def initialize(key:, label:, type:, column:, operators:, pickable: nil, short_key: key,
      group: nil, options: nil, catalog: true, variant_group: nil, operand_min: nil, sign: nil)
      @key = key.to_sym
      @short_key = short_key.to_sym
      @label = label
      @group = group
      @type = type
      @column = column
      @options = options
      @catalog = catalog
      @variant_group = variant_group
      @operand_min = operand_min
      @sign = sign&.to_sym
      @operators = operators.map(&:to_sym).index_with { |k| type.operator(k) }
      @declared_pickable = pickable&.map(&:to_sym)
      validate_pickable!
    end

    def catalog?
      @catalog
    end

    # Everything the attribute accepts (URL, fixed slots, presets, compiling).
    def operators
      @operators.values
    end

    def operator(key)
      @operators[key] # nil if not offered on this attribute
    end

    # The subset the editor offers, in the accepted list's declaration order.
    def pickable_operators
      operators.select { |o| pickable?(o.key) }
    end

    def pickable?(key)
      pickable_keys.include?(key.to_sym)
    end

    # Copy with a replaced operator list (used by Schema#operators in derive).
    # A declared pickable list is narrowed along with it -- never widened back
    # to "all", which would silently offer operators the host had hidden.
    def with_operators(operator_keys)
      keys = operator_keys.map(&:to_sym)
      copy(operators: keys, pickable: @declared_pickable && (@declared_pickable & keys))
    end

    # Copy with the column resolved against a concrete base relation.
    def resolved_against(base)
      table = base.arel_table
      resolved =
        case column
        when Symbol then table[column]
        when Proc then column.call(table)
        else column
        end
      copy(operators: @operators.keys, pickable: @declared_pickable, column: resolved)
    end

    def as_json(*)
      {key: key, label: label, group: group, variant_group: variant_group, sign: sign,
       type: type.key, control: type.control, operand_min: operand_min,
       operators: operators.map { |o| o.as_json.merge(pickable: pickable?(o.key)) },
       options: options&.descriptor}
    end

    private

    def pickable_keys
      @declared_pickable || @operators.keys
    end

    def copy(operators:, pickable:, column: self.column)
      self.class.new(key: key, label: label, type: type, column: column,
        operators: operators, pickable: pickable, short_key: short_key, group: group,
        options: @options, catalog: @catalog, variant_group: variant_group,
        operand_min: operand_min, sign: sign)
    end

    # Host-authored like the operator list itself, so an operator that is
    # pickable without being accepted is a typo and fails loud.
    def validate_pickable!
      unknown = Array(@declared_pickable) - @operators.keys
      return if unknown.empty?

      raise ArgumentError, "attribute #{key}: pickable operator(s) #{unknown.inspect} " \
                           "are not in its operators #{@operators.keys.inspect}"
    end
  end
end
