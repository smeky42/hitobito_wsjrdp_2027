# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The APPLIED user filter of one expandable table, worded as compact chips for
# the table's filter line (doc/wsjrdp/expandable_table.md).
#
# ONE CHIP PER SLOT, in slot order. A slot is an OR, so its conditions are joined
# with " oder " -- and the slot is the smallest unit the line can show or drop
# without changing what the rest of the filter means (slots are ANDed).
#
# ONLY THE USER PART IS CHIPPED. Fixed slots never reach this class:
# `state.filter.user_slots` is the user half alone (the fixed half lives in
# `fixed_slots` / `readonly_slots`), and a pin the user cannot remove has no
# business in a line of removable chips -- the builder renders those as locked
# chips instead.
#
# A SLOT THAT EQUALS AN ACTIVE PRESET'S SLOT IS LEFT OUT: the preset toggle
# already shows that state, so a chip would say it a second time. Equality is the
# one rule of Wsjrdp::Filtering::SlotEquality (the same SET of conditions,
# operands compared canonically, the two members of a sign pair one and the same
# under a sign-invariant operator) -- the very rule that decided
# `preset.active?`, which is why an INACTIVE preset can never drop anything. The
# sign pairs come from the catalog itself, so the chips need nothing the class
# is not handed already.
#
# A GROUP'S OWN SLOT IS LEFT OUT TOO. The members of a quick-select group share
# ONE slot -- `attribute in (values)`, one value per member -- and every pressed
# button says its own value, so a slot of exactly that shape (one condition, the
# group's attribute, the `in` operator) whose values are ALL member values of the
# group gets no chip, whichever of the buttons are pressed. One value that
# belongs to no member and the chip stays: no button can say that one. A slot
# with a second OR condition is not the group's and keeps its chip as well.
#
# Of a preset only `slots` and `active?` are used, and of a group member only
# `group?`, `attribute` and `group_values`, so any object answering those works
# (Wsjrdp::TableState::FilterPreset is what the state hands over).
#
# Pure value logic over the catalog Hash and the applied tree -- no Rails, no
# database, no view (spec/domain/wsjrdp/filter_chips_spec.rb runs it standalone).
#
#   chips = Wsjrdp::FilterChips.new(catalog: state.filter.full_catalog,
#     user_slots: state.filter.user_slots, presets: state.filter.presets)
#   chips.chips.map(&:text) # => ["Kostenstelle ist eines von 3150, 3160", ...]
#   chips.count             # => 3 -- conditions over all chips, for a badge
#
# The FULL catalog is the right one to pass: an attribute the picker hides
# (`exclude:`) can still arrive through a hand-written URL, and it should get its
# words rather than its bare key.
class Wsjrdp::FilterChips
  # One chip = one slot of the applied user filter.
  #
  #   text        the whole slot as one line ("Betrag im Bereich 100 – 500")
  #   conditions  its conditions worded one by one -- what `text` joins with OR
  #   slot        the raw slot, so a chip can act on itself (removing it is
  #               SlotEquality.remove_slots(user_slots, [slot]) re-encoded)
  Chip = Data.define(:text, :conditions, :slot)

  # The operator the members of a quick-select group share their slot under.
  GROUP_OPERATOR = "in"

  OR_JOIN = " oder "   # within a slot -- the builder's own connector word
  RANGE_JOIN = " – "   # the two operands of a range (en dash, as in the builder)
  LIST_JOIN = ", "     # several operands of a set operator

  DAY_PATTERN = /\A(\d{4})-(\d{2})-(\d{2})\z/
  MONTH_PATTERN = /\A(\d{4})-(\d{2})\z/

  attr_reader :chips

  def initialize(catalog:, user_slots:, presets: [])
    @attributes = index_attributes(catalog)
    @sign_aliases = sign_aliases(catalog)
    @chips = build_chips(user_slots, presets)
    freeze
  end

  def any? = @chips.any?

  def empty? = @chips.empty?

  # Conditions over ALL chips (what a badge on the filter line counts).
  def count = @chips.sum { |chip| chip.conditions.size }

  private

  # {"amount" => attribute Hash}: the catalog's attribute keys are Symbols, a
  # condition's are Strings (Query#as_json), so the index is by String.
  def index_attributes(catalog)
    Array((catalog || {})[:attributes]).each_with_object({}) do |attribute, index|
      index[attribute[:key].to_s] = attribute
    end
  end

  # The catalog's sign PAIRS as {signed key => absolute key}, the map
  # Wsjrdp::Filtering::SlotEquality canonicalises a sign-invariant condition by
  # (Wsjrdp::Filtering::Schema#sign_aliases builds the same thing from the
  # schema). A group whose two members do not both reach the catalog is skipped.
  def sign_aliases(catalog)
    Array((catalog || {})[:attributes])
      .select { |attribute| attribute[:variant_group] && attribute[:sign] }
      .group_by { |attribute| attribute[:variant_group] }
      .each_with_object({}) do |(_group, members), map|
        signed = members.find { |attribute| attribute[:sign].to_s == "signed" }
        absolute = members.find { |attribute| attribute[:sign].to_s == "absolute" }
        map[signed[:key].to_s] = absolute[:key].to_s if signed && absolute
      end
  end

  def build_chips(user_slots, presets)
    slots = Wsjrdp::Filtering::SlotEquality
      .remove_slots(Array(user_slots), active_preset_slots(presets), aliases: @sign_aliases)
    group_values = group_values_by_attribute(presets)
    slots.filter_map { |slot|
      next if group_slot?(slot, group_values)

      conditions = Array(slot).map { |condition| condition_text(condition) }.freeze
      next if conditions.empty? # a slot without conditions has nothing to say

      Chip.new(text: conditions.join(OR_JOIN), conditions: conditions, slot: slot)
    }.freeze
  end

  def active_preset_slots(presets)
    Array(presets).select(&:active?).flat_map { |preset| Array(preset.slots) }
  end

  # {attribute key => the values its group members carry}. Several groups on one
  # attribute -- nothing forbids it -- simply contribute their values together.
  def group_values_by_attribute(presets)
    Array(presets).select(&:group?).each_with_object({}) do |member, map|
      (map[member.attribute.to_s] ||= []).concat(Array(member.group_values).map(&:to_s))
    end
  end

  # Is this slot one a group's buttons say in full? One condition, on an
  # attribute a group speaks for, under the GROUP_OPERATOR, and every one of its
  # values a member's. A slot without any value at all keeps its chip: no button
  # is pressed for it, so nothing else would show it.
  def group_slot?(slot, group_values)
    conditions = Array(slot)
    return false unless conditions.size == 1

    key, operator, *operands = Array(conditions.first)
    values = group_values[key.to_s]
    return false unless values && operator.to_s == GROUP_OPERATOR

    operands.any? && operands.all? { |operand| values.include?(operand.to_s) }
  end

  # THE wording of one condition, mirroring the filter builder's `condFullText`
  # (app/views/shared/wsjrdp/filtering/_builder.html.haml), so the line, the
  # builder's chips and their tooltips say the same thing:
  #
  #   "<attribute label> <operator label> <operands>"
  #
  #   * `label_many` instead of `label` as soon as an operator that HAS one gets
  #     2+ operands ("ist eines von" makes the ANY-of semantics visible);
  #   * operands of a reference/enum attribute are shown by their OPTION LABEL
  #     (an unknown value falls back to the value itself), several joined by ", ";
  #   * a range operator (arity :two) joins its two operands with an en dash;
  #   * an operand-less operator (hat Wert / ist leer / ≠ 0) is the attribute plus
  #     the operator label and nothing else;
  #   * an attribute or operator the catalog does not know falls back to its KEY,
  #     so a hand-written URL still reads as something.
  #
  # Case sensitivity needs no suffix: the case-sensitive member of an operator
  # pair carries it in its own label ("enthält (Groß/Klein)").
  #
  # Deviations from the JS, deliberate: no truncation (`condText`'s 28-char cut
  # and its "+n" for long operand lists are the builder's chip LAYOUT, not the
  # wording -- `condFullText` has neither), and no trailing blank in the
  # unknown-attribute fallback.
  def condition_text(condition)
    key, operator_key, *operands = Array(condition)
    attribute = @attributes[key.to_s]
    return join_parts(key, operator_key, operands.map(&:to_s).join(LIST_JOIN)) unless attribute

    operator = find_operator(attribute, operator_key)
    join_parts(attribute[:label], operator_label(operator, operator_key, operands),
      operands_text(attribute, operator, operands))
  end

  def join_parts(*parts) = parts.map(&:to_s).reject(&:empty?).join(" ")

  def find_operator(attribute, key)
    Array(attribute[:operators]).find { |operator| operator[:key].to_s == key.to_s }
  end

  def operator_label(operator, operator_key, operands)
    return operator_key.to_s unless operator

    label = ((operands.size > 1) && operator[:label_many]) || operator[:label]
    label.to_s
  end

  def operands_text(attribute, operator, operands)
    return "" if operands.empty?
    return range_text(attribute, operands) if operator && operator[:arity].to_s == "two"

    operands.map { |operand| operand_text(attribute, operand) }.join(LIST_JOIN)
  end

  def range_text(attribute, operands)
    operands.first(2).map { |operand| operand_text(attribute, operand) }.join(RANGE_JOIN)
  end

  # One operand, mirroring the builder's `fmtOperandFull` -- the untruncated
  # variant of `fmtOperand` -- which dispatches on the attribute's CONTROL.
  def operand_text(attribute, operand)
    case attribute[:control].to_s
    when "multiselect", "select" then option_label(attribute, operand)
    when "date_range" then date_text(operand)
    when "number_range" then operand.is_a?(Numeric) ? number_text(operand) : operand.to_s
    else operand.to_s
    end
  end

  def option_label(attribute, operand)
    pair = Array(attribute.dig(:options, :values))
      .find { |value, _| value.to_s == operand.to_s }
    pair ? pair.last.to_s : operand.to_s
  end

  # ISO -> German, the two forms the date control emits ("2026-05-01" from a day
  # picker, "2026-05" from the month operator); anything else stands as it is.
  def date_text(operand)
    text = operand.to_s
    day = DAY_PATTERN.match(text)
    return "#{day[3]}.#{day[2]}.#{day[1]}" if day

    month = MONTH_PATTERN.match(text)
    month ? "#{month[2]}.#{month[1]}" : text
  end

  # 1234567.5 -> "1.234.567,5", the builder's `toLocaleString("de-DE")`.
  def number_text(operand)
    ActiveSupport::NumberHelper.number_to_delimited(operand, delimiter: ".", separator: ",")
  end
end
