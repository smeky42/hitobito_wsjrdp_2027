# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module FinanceTextHelper
  # An amount within a sentence: "1.700€", "123,45€".
  def cents_in_prose(cents)
    format_cents_de(cents, space: "", zero_cents: "")
  end

  def warning_triangle_icon
    tag.i(class: "fas fa-exclamation-triangle me-1", "aria-hidden": "true")
  end
end
