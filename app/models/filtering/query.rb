# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Filtering
  # The user-built CNF tree. Wire form (JSON) is compact and positional:
  # an array of slots; a slot is an array of conditions; a condition is the
  # flat array [attribute, operator, *operands]. Attribute/operator use their
  # REGULAR keys in JSON (the URL codec swaps in short_keys); internally they
  # are symbols to match the registry (interning is safe -- symbols are GC'd).
  Query = Data.define(:slots) do
    def self.empty
      new(slots: [])
    end

    def self.parse(tree)
      slots = Array(tree).map do |conditions|
        Slot.new(conditions: Array(conditions).filter_map { |c|
          next unless c.is_a?(Array)

          attr, op, *operands = c
          next if attr.nil? || op.nil?

          Condition.new(attribute: attr.to_s.to_sym, operator: op.to_s.to_sym,
            operands: operands)
        })
      end
      new(slots: slots)
    end

    def empty?
      slots.all? { |s| s.conditions.empty? }
    end

    def condition_count
      slots.sum { |s| s.conditions.size }
    end

    def as_json(*)
      slots.map { |s|
        s.conditions.map { |c| [c.attribute.to_s, c.operator.to_s, *c.operands] }
      }
    end
  end
end
