# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A graphical tooltip: `trigger` with a box on hover that shows `lines`, one
# [label, value] pair per line -- the value may be HTML (a role badge). The
# box, its style and its script: shared/wsjrdp/_tip, rendered with the first
# tooltip of a request.
module WsjrdpTipHelper
  def wsjrdp_tip(trigger, lines:, aria_label: nil)
    tip = tag.template(class: "wsjrdp-tip") do
      safe_join(lines.map { |label, value|
        tag.div(safe_join([(tag.span("#{label}:", class: "wsjrdp-tip-label") if label.present?), value].compact, " "))
      })
    end
    aria = aria_label || lines.map { |label, value| [label, strip_tags(value.to_s)].compact_blank.join(": ") }.join(", ")
    safe_join([render("shared/wsjrdp/tip"), tag.span(safe_join([trigger, tip]), class: "wsjrdp-tip-host", "aria-label": aria)])
  end
end
