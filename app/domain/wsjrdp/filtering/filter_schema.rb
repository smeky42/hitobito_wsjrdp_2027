# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Filtering
  # THE FILTER SCHEMA PROTOCOL -- everything a table's `filter:` policy needs from
  # one dataset, in one place. A dataset module declares its SCHEMA plus a
  # `bound(except:)` method and extends this module:
  #
  #   module Fin::DatevBookingsFilterSchema
  #     extend Wsjrdp::Filtering::FilterSchema
  #     SCHEMA = Wsjrdp::Filtering::Schema.define { |s| ... }
  #     def self.bound(except: nil) = SCHEMA.bind(DatevBooking.left_joins(:batch), except: except)
  #   end
  #
  # The table then names it once, at class level:
  #
  #   filter: {policy: :remember, schema: Fin::DatevBookingsFilterSchema, exclude: %i[sphere]}
  #
  # and Wsjrdp::TableState::Filter talks ONLY to these methods. No host decodes,
  # validates or compiles a filter itself any more.
  #
  # NOT to be confused with Wsjrdp::Filtering::Schema, which is the attribute
  # catalog a dataset module declares (and binds to a relation), nor with
  # Wsjrdp::Filtering::Type, which is the value type (decimal / date / text ...)
  # of ONE attribute.
  #
  # TWO KINDS OF INPUT, TWO LEVELS OF STRICTNESS -- the point of the protocol:
  #
  #   USER input (the URL param, a store entry, the builder's posted tree) is
  #   untrusted and handled TOLERANTLY: #decode / #encode_tree drop whatever the
  #   schema does not know, so a hand-edited or stale value yields fewer
  #   conditions -- never an error, and never a wider scope.
  #
  #   HOST input (the policy's fixed slots and its default tree) is CODE and is
  #   handled STRICTLY: #parse_fixed! raises on an attribute or operator the
  #   schema does not know, on a wrong operand count and on an operand that does
  #   not cast. Wsjrdp::Filtering::Compiler is deliberately neutral-on-invalid,
  #   so without this a typo in a pinned slot -- or an attribute later removed
  #   from the schema -- would be dropped SILENTLY and WIDEN the page scope.
  #   That is exactly the failure this protocol exists to prevent.
  module FilterSchema
    # bound(except: nil) -> BoundSchema is implemented by the dataset module
    # itself: it is the only part that knows the base relation and the joins its
    # attributes need.

    # Wire form (the Rison of the `f` param / the store) -> Query. Tolerant:
    # unknown attributes and operators are dropped, blank or malformed input
    # yields the empty query.
    def decode(raw, schema:)
      Wsjrdp::Filtering::UrlCodec.decode(raw, schema: schema)
    end

    # Query -> wire form (Rison with short keys), or nil when nothing survives.
    def encode(query, schema:)
      Wsjrdp::Filtering::UrlCodec.encode(query, schema: schema)
    end

    # The filter builder's posted JSON tree (long keys) -> wire form, or nil.
    # Tolerant like #decode -- the tree comes from the browser.
    def encode_tree(tree, schema:)
      encode(Wsjrdp::Filtering::Query.parse(tree), schema: schema)
    end

    # A HOST-authored CNF tree -> Query, STRICTLY (see the note above). Raises an
    # ArgumentError naming the attribute, the operator and the slot index for
    # anything the schema does not know, and for a blank or malformed tree.
    # `what:` only labels the message ("fixed slot" / "filter default tree").
    #
    # Every fixed entry's slots are parsed in ONE call, so the slot index counts
    # across all of a table's fixed slots, in declaration order.
    def parse_fixed!(tree, schema:, what: "fixed slot")
      slots = Array(tree)
      raise ArgumentError, "#{what}: empty filter tree" if slots.empty?

      parsed = slots.each_with_index.map do |raw_conditions, index|
        conditions = Array(raw_conditions)
        raise ArgumentError, "#{what} #{index}: slot without conditions" if conditions.empty?

        Wsjrdp::Filtering::Slot.new(
          conditions: conditions.map { |c| parse_fixed_condition!(c, schema, what, index) }
        )
      end
      Wsjrdp::Filtering::Query.new(slots: parsed)
    end

    # Query + relation -> filtered relation. `query` may be nil ("no conditions"),
    # which still merges the schema's own base relation -- that is where the
    # joins the attributes need live (the bookings' left_joins(:batch), the Moss
    # expenses/bookings joins), so no host ever repeats them.
    def compile(query, schema:, relation:)
      relation = relation.merge(schema.base)
      return relation if query.nil?

      Wsjrdp::Filtering::Compiler.new(schema).apply(query, relation: relation)
    end

    private

    def parse_fixed_condition!(condition, schema, what, index)
      unless condition.is_a?(Array)
        raise ArgumentError, "#{what} #{index}: condition must be an Array " \
                             "[attribute, operator, *operands], got #{condition.class}"
      end
      raw_attribute, raw_operator, *operands = condition
      if raw_attribute.nil? || raw_operator.nil?
        raise ArgumentError, "#{what} #{index}: condition must name an attribute and an operator"
      end

      attribute = schema.find(raw_attribute) ||
        raise(ArgumentError, "#{what} #{index}: unknown attribute #{raw_attribute.inspect} " \
                             "(operator #{raw_operator.inspect})")
      # Host-authored trees use the LONG keys (D2b); short keys are a wire form
      # and are deliberately not accepted here.
      operator = attribute.operator(raw_operator.to_s.to_sym) ||
        raise(ArgumentError, "#{what} #{index}: attribute #{raw_attribute.inspect} does not " \
                             "offer operator #{raw_operator.inspect}")
      validate_fixed_operands!(attribute, operator, operands, what, index)
      Wsjrdp::Filtering::Condition.new(attribute: attribute.key, operator: operator.key,
        operands: operands)
    end

    # The compiler also drops a condition whose operands do not cast or whose
    # count the operator does not accept -- so a fixed slot has to survive those
    # two checks here as well, or the pin would be lost just as silently.
    # Operand VALUES never appear in the message.
    def validate_fixed_operands!(attribute, operator, operands, what, index)
      where = "#{what} #{index}: attribute #{attribute.key.inspect} operator #{operator.key.inspect}"
      cast = operator.cast || attribute.type.method(:cast)
      values = operands.map { |value| cast.call(value) }
      raise ArgumentError, "#{where} has an operand its type cannot cast" if values.any?(&:nil?)
      return if operator.arity_satisfied?(values)

      raise ArgumentError, "#{where} expects arity #{operator.arity}, got #{values.size} operand(s)"
    end
  end
end
