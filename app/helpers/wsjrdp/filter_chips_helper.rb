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
end
