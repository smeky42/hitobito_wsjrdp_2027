# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Prepended to the core's SheetHelper (lib/hitobito_wsjrdp_2027/wagon.rb). The
# core layout reads the sheet's title twice: `%title= "… - #{title}"` in the
# head and `%h1= title` inside the block it hands to render_sheets /
# render_current_sheet. A Wsjrdp::SheetTitle carries markup for the h1; this
# answers it inside that block and the plain text everywhere else, so the
# browser tab never shows tags.
module Wsjrdp2027::SheetHelper
  def title(string = nil)
    value = super
    return value unless string.nil? && value.is_a?(Wsjrdp::SheetTitle)

    wsjrdp_in_sheet_body? ? value.html : value.plain
  end

  def render_sheets(&) = wsjrdp_sheet_body { super }

  def render_current_sheet(&) = wsjrdp_sheet_body { super }

  private

  # rubocop:disable Rails/HelperInstanceVariable -- response-local render state
  def wsjrdp_sheet_body
    outer = @wsjrdp_sheet_body
    @wsjrdp_sheet_body = true
    yield
  ensure
    @wsjrdp_sheet_body = outer
  end

  def wsjrdp_in_sheet_body? = @wsjrdp_sheet_body
  # rubocop:enable Rails/HelperInstanceVariable
end
