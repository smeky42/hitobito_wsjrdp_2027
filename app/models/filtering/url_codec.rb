# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "rison"

module Filtering
  # Query <-> the ?filter= URL parameter. The URL form is the compact
  # positional tree in Rison, with every attribute/operator replaced by its
  # short_key. Decoding therefore needs the schema (short_key -> key); it also
  # accepts the full keys, so hand-edited URLs may use either. Anything
  # unknown or malformed is dropped (allow-list; "empty is neutral") -- a
  # garbage ?filter= yields the unfiltered page, never an error.
  module UrlCodec
    module_function

    # Query -> Rison string with short keys, or nil when nothing survives
    # canonicalization (unknown attributes/operators are dropped here too).
    def encode(query, schema:)
      tree = query.slots.filter_map { |slot|
        conditions = slot.conditions.filter_map { |c|
          attribute = schema.find(c.attribute) or next
          operator = attribute.operator(c.operator) or next
          [attribute.short_key, operator.short_key, *c.operands]
        }
        conditions.presence
      }
      tree.empty? ? nil : ::Rison.dump(tree)
    end

    # ?filter= value -> Query. Blank or malformed input -> empty query.
    def decode(param, schema:)
      return Query.empty if param.blank?

      tree = ::Rison.load(param.to_s)
      slots = Array(tree).map { |conditions|
        Slot.new(conditions: Array(conditions).filter_map { |c|
          next unless c.is_a?(Array)

          raw_attr, raw_op, *operands = c
          attribute = resolve_attribute(schema, raw_attr) or next
          operator = resolve_operator(attribute, raw_op) or next
          Condition.new(attribute: attribute.key, operator: operator.key,
            operands: operands)
        })
      }
      Query.new(slots: slots)
    rescue ::Rison::ParseError
      Query.empty
    end

    # Percent-encode only what would break URL/query parsing (&, +, #, %,
    # whitespace, ;, ?); everything else stays readable. The result is placed
    # directly as the query value -- never additionally form-encoded.
    def escape_for_query(rison)
      rison.gsub(/[%&+#;?\s]/) { |c| format("%%%02X", c.ord) }
    end

    def resolve_attribute(schema, raw)
      key = raw.to_s.to_sym
      schema.attributes[key] ||
        schema.attributes.values.find { |a| a.short_key == key }
    end

    def resolve_operator(attribute, raw)
      key = raw.to_s.to_sym
      attribute.operator(key) ||
        attribute.operators.find { |o| o.short_key == key }
    end
  end
end
