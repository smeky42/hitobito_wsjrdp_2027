# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Filtering
  # One filterable attribute of a dataset.
  #
  # operators: REQUIRED -- the explicit list of operator keys this attribute
  #   supports, resolved against the type's implementation library. Nothing is
  #   derived implicitly from the type; an unknown key raises at declaration
  #   time (host-authored, so fail loud).
  # short_key: short name used in the URL (Rison) encoding only; JSON tree and
  #   catalog always use the full key. Defaults to the key itself.
  # column: in a bound schema an Arel attribute / expression (or an array for
  #   multi-column types). In a TEMPLATE: a symbol (resolved as
  #   base.arel_table[sym] at bind time) or a lambda ->(t) { ... } receiving
  #   the arel_table (may return an array).
  # options: a Filtering::Options describing how the UI gets [value, label]
  #   pairs (only for reference/enum controls).
  # catalog: false = registered for compilation only, omitted from the catalog
  #   (so it can back a hidden condition without a UI control).
  # variant_group: several attributes may form ONE entry in the attribute
  #   picker (labelled with this string); the editor then offers the group
  #   members as sub-variants (e.g. the text search over Buchungstext /
  #   Belege / both). The first declared member is the group's default.
  class Attribute
    attr_reader :key, :short_key, :label, :group, :type, :column, :options,
      :variant_group

    def initialize(key:, label:, type:, column:, operators:, short_key: key,
      group: nil, options: nil, catalog: true, variant_group: nil)
      @key = key.to_sym
      @short_key = short_key.to_sym
      @label = label
      @group = group
      @type = type
      @column = column
      @options = options
      @catalog = catalog
      @variant_group = variant_group
      @operators = operators.map(&:to_sym).index_with { |k| type.operator(k) }
    end

    def catalog?
      @catalog
    end

    def operators
      @operators.values
    end

    def operator(key)
      @operators[key] # nil if not offered on this attribute
    end

    # Copy with a replaced operator list (used by Schema#operators in derive).
    def with_operators(operator_keys)
      self.class.new(key: key, label: label, type: type, column: column,
        operators: operator_keys, short_key: short_key, group: group,
        options: @options, catalog: @catalog, variant_group: variant_group)
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
      self.class.new(key: key, label: label, type: type, column: resolved,
        operators: @operators.keys, short_key: short_key, group: group,
        options: @options, catalog: @catalog, variant_group: variant_group)
    end

    def as_json(*)
      {key: key, label: label, group: group, variant_group: variant_group,
       type: type.key, control: type.control,
       operators: operators.map(&:as_json),
       options: options&.descriptor}
    end
  end
end
