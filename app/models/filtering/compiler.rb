# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Filtering
  # Query + BoundSchema -> filtered ActiveRecord::Relation, via Arel with
  # bound values only. Allow-listed and neutral-on-invalid: an unknown
  # attribute/operator or an operand that fails casting/arity drops that
  # condition; a slot without valid conditions is skipped ("empty is
  # neutral"). SQL three-valued logic is inherited as-is (no NULL coalescing).
  class Compiler
    def initialize(schema)
      @schema = schema # a BoundSchema (columns resolved)
    end

    # `hidden` are host-supplied slots AND-combined ahead of the user's slots;
    # they are never read from params and never serialized, so they cannot be
    # bypassed. (v1: they fail as silently as user input -- documented
    # loophole, see doc §2.3.)
    def apply(query, relation: @schema.base, hidden: [])
      (hidden + query.slots).filter_map { |slot| slot_predicate(slot) }
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
