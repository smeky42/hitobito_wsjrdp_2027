# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Filtering
  # Query + BoundSchema -> filtered ActiveRecord::Relation, via Arel with
  # bound values only. Allow-listed and neutral-on-invalid: an unknown
  # attribute/operator or an operand that fails casting/arity drops that
  # condition; a slot without valid conditions is skipped ("empty is
  # neutral"). SQL three-valued logic is inherited as-is (no NULL coalescing).
  #
  # NEUTRAL-ON-INVALID IS ONLY SAFE FOR USER INPUT. Everything the compiler sees
  # is a Query the table state already parsed: the user's part tolerantly (a
  # dropped condition can only NARROW the user's own filter), a host-pinned slot
  # STRICTLY (Wsjrdp::Filtering::FilterSchema#parse_fixed! raises instead of
  # letting a typo drop the pin and widen the page scope). There is deliberately
  # no way to hand the compiler a raw, unparsed tree -- the former `hidden:`
  # argument was exactly that and is gone; host-pinned conditions are the
  # policy's fixed slots.
  class Compiler
    def initialize(schema)
      @schema = schema # a BoundSchema (columns resolved)
    end

    def apply(query, relation: @schema.base)
      query.slots.filter_map { |slot| slot_predicate(slot) }
        .reduce(relation) { |rel, pred| rel.where(pred) } # AND across slots
    end

    private

    def slot_predicate(slot)
      slot.conditions.filter_map { |c| condition_predicate(c) }
        .reduce { |a, b| a.or(b) } # OR within slot; nil if empty -> skipped
    end

    def condition_predicate(cond)
      attribute = @schema.find(cond.attribute) or return nil
      operator = attribute.operator(cond.operator) or return nil
      cast = operator.cast || attribute.type.method(:cast)
      operands = cond.operands.map { |v| cast.call(v) }
      return nil if operands.any?(&:nil?)
      return nil unless operator.arity_satisfied?(operands)

      operator.to_arel(attribute.column, operands)
    end
  end
end
