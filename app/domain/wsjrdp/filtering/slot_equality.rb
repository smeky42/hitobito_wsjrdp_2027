# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "bigdecimal"

module Wsjrdp::Filtering
  # THE equality of two CNF slots, in one place -- what a filter PRESET is
  # recognised by (doc/wsjrdp/expandable_table.md, "Presets").
  #
  # THE RULE: two slots are equal iff they hold the SAME SET of conditions --
  # same attribute, same operator, same operands; the order of the conditions
  # within a slot is irrelevant (a slot is an OR, which commutes), and a repeated
  # condition adds nothing. A slot that carries a preset's condition PLUS further
  # OR conditions is therefore NOT equal to it: an added OR widens the slot, so
  # the preset's promise ("only rows matching this") no longer holds.
  #
  # A condition is canonicalised by stringifying every element, so a wire value
  # and a host-written literal of the same operand match (`0` == `"0"`; the
  # attribute and operator keys are already the LONG ones on both sides -- the
  # user half through Wsjrdp::Filtering::UrlCodec#decode, the host half through
  # Wsjrdp::Filtering::FilterSchema#parse_fixed!).
  #
  # SIGN PAIRS (`aliases:`): the two members of an amount's sign pair -- the
  # signed column and its ABS() twin (Wsjrdp::Filtering::Attribute#sign) -- are
  # ONE predicate under a SIGN-INVARIANT operator. `≠ 0`, `hat Wert`, `ist leer`
  # and `= 0` ask nothing about the sign, so `Saldo ≠ 0` and `|Saldo| ≠ 0` select
  # the same rows and count as the same condition; a preset on the magnitude is
  # therefore active on the signed twin too, and its toggle removes it.
  # `aliases:` is that pairing, {signed key => absolute key}
  # (Wsjrdp::Filtering::Schema#sign_aliases), and canonicalises such a condition
  # to the ABSOLUTE member. Comparisons stay member-specific: `|Saldo| ≥ 100`
  # and `Saldo ≥ 100` are different questions, as are `= 5` and `= -5`. Without
  # `aliases:` (the default) every attribute stands for itself.
  #
  # Deliberately dependency-free (plain Ruby, no Rails, no Arel): the table
  # state's standalone spec requires it directly. The filter builder's JS applies
  # the same rule for its cosmetic slot marking -- keep the two in step.
  module SlotEquality
    # Separators no attribute key, operator key or operand can contain, so the
    # joined form is unambiguous.
    CONDITION_SEPARATOR = "\u0000"
    SLOT_SEPARATOR = "\u0001"

    # Operand-less operators that ask nothing about the sign of the value.
    # `eq` joins them for the single operand zero, which #sign_invariant?
    # recognises NUMERICALLY, however it is written (`0`, `0.0`, `-0`). The
    # operands themselves keep being compared by their string form, so `= 0`
    # and `= 0.0` remain two conditions -- on both members of the pair alike.
    SIGN_INVARIANT_OPERATORS = %w[nonzero present blank].freeze

    module_function

    # One condition as a comparable String, e.g. "booking_count\u0000gt\u00000".
    def condition_key(condition, aliases: {})
      attribute, *rest = Array(condition).map(&:to_s)
      return "" if attribute.nil?

      [canonical_attribute(attribute, rest, aliases), *rest].join(CONDITION_SEPARATOR)
    end

    # One slot as a comparable String: its conditions deduplicated and sorted, so
    # equality is set equality.
    def slot_key(slot, aliases: {})
      Array(slot).map { |condition| condition_key(condition, aliases: aliases) }
        .uniq.sort.join(SLOT_SEPARATOR)
    end

    def same_slot?(one, other, aliases: {})
      slot_key(one, aliases: aliases) == slot_key(other, aliases: aliases)
    end

    # Does `slots` contain a slot equal to `slot`?
    def include_slot?(slots, slot, aliases: {})
      key = slot_key(slot, aliases: aliases)
      Array(slots).any? { |other| slot_key(other, aliases: aliases) == key }
    end

    # `slots` without every slot equal to one of `removed`.
    def remove_slots(slots, removed, aliases: {})
      keys = Array(removed).map { |slot| slot_key(slot, aliases: aliases) }
      Array(slots).reject { |slot| keys.include?(slot_key(slot, aliases: aliases)) }
    end

    # The `wanted` slots that `slots` does not already contain.
    def missing_slots(slots, wanted, aliases: {})
      keys = Array(slots).map { |slot| slot_key(slot, aliases: aliases) }
      Array(wanted).reject { |slot| keys.include?(slot_key(slot, aliases: aliases)) }
    end

    # The attribute a condition is compared under: its own key, or -- for a
    # sign-invariant condition on the signed member of a sign pair -- the pair's
    # absolute member.
    def canonical_attribute(attribute, rest, aliases)
      return attribute unless sign_invariant?(rest)

      (aliases || {})[attribute] || attribute
    end

    # `rest` is a condition without its attribute: [operator, *operands],
    # stringified.
    def sign_invariant?(rest)
      operator, *operands = rest
      return true if SIGN_INVARIANT_OPERATORS.include?(operator)

      operator == "eq" && operands.size == 1 && zero_operand?(operands.first)
    end

    # Numerically zero, however the operand is written ("0", "0.0", "-0").
    def zero_operand?(operand)
      BigDecimal(operand.to_s).zero?
    rescue ArgumentError, TypeError
      false
    end
  end
end
