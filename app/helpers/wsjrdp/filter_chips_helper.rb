# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The filter line's chips: the APPLIED user filter of an expandable table,
# worded as one chip per CNF slot (Wsjrdp::FilterChips).
#
# Like every other helper of the widget this only READS the state built by the
# controller (Wsjrdp::TableStateful); it never looks at params, session or
# cookies.
module Wsjrdp::FilterChipsHelper
  # The chips of `state`'s applied user filter, in slot order -- Chip values with
  # `text`, `conditions` and the raw `slot`.
  #
  # The FULL catalog is passed on purpose: an attribute the picker hides
  # (`exclude:`) can still reach the applied filter through a hand-written URL,
  # and it should be worded rather than shown as a bare key. Slots equal to an
  # ACTIVE preset's are left out -- the preset toggle already shows them.
  #
  # `presets` is the RESOLVED preset list the widget hands to the filter line
  # and the builder (policy-declared or view-declared); it defaults to the
  # policy's own, which is the same list whenever the view declares none.
  def et_filter_chips(state, presets: state.filter.presets)
    Wsjrdp::FilterChips.new(catalog: state.filter.full_catalog,
      user_slots: state.filter.user_slots, presets: presets).chips
  end

  # The fixed conditions the user sees but cannot change (show: :readonly), as
  # chips worded the same way -- one per slot, labelled from the FULL catalog
  # (a pin may use an attribute the picker does not offer).
  def et_filter_locked_chips(state)
    return [] if state.filter.readonly_slots.empty?

    Wsjrdp::FilterChips.new(catalog: state.filter.full_catalog, user_slots: state.filter.readonly_slots).chips
  end

  # A chip's words, an option's prefix muted and light (.flt-opt-prefix):
  # what `chip.text` says, with that part set apart.
  def et_filter_chip_content(chip)
    safe_join(chip.parts.map { |part| et_filter_part_content(part) }, Wsjrdp::FilterChips::OR_JOIN)
  end

  # The HTML of a chip's tooltip (shared/wsjrdp/_html_tooltip_js): each
  # condition's attribute and operator, then its operands one per line, an
  # option's prefix muted; `hint` (what a click does) muted at the end.
  def et_filter_chip_tip(chip, hint: nil)
    lines = chip.parts.each_with_index.flat_map do |part, index|
      head = safe_join([content_tag(:b, part.label), " ", part.operator])
      [(content_tag(:div, "oder", class: "wsjrdp-tip-muted") if index.positive?), content_tag(:div, head),
        *part.operands.map { |prefix, text| content_tag(:div, et_filter_operand(prefix, text), class: "flt-tip-operand") }]
    end
    lines << content_tag(:div, hint, class: "wsjrdp-tip-muted mt-1") if hint
    content_tag(:div, safe_join(lines.compact), class: "flt-tip").to_str
  end

  private

  def et_filter_part_content(part)
    operands = safe_join(part.operands.map { |prefix, text| et_filter_operand(prefix, text) }, part.join)
    safe_join([part.label, part.operator, (operands if part.operands.any?)].compact, " ")
  end

  def et_filter_operand(prefix, text)
    return text if prefix.blank?

    safe_join([content_tag(:span, prefix, class: "flt-opt-prefix"), text], " ")
  end
end
