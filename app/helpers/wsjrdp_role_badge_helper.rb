# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A role as a coloured badge, in the colours of Wsjrdp2027::RoleColors. The
# stylesheet (shared/wsjrdp/_role_styles) comes with the first badge of a
# request, so a page needs nothing but the helper.
module WsjrdpRoleBadgeHelper
  def wsjrdp_role_badge(role, class: nil, title: nil)
    return "".html_safe if role.blank?

    css = ["wsjrdp-role", Wsjrdp2027::RoleColors.css_class(role), binding.local_variable_get(:class)]
    safe_join([render("shared/wsjrdp/role_styles"), tag.span(role, class: css.compact, title: title)])
  end

  # A person's two roles: the common one as one badge, both -- the contingent's
  # first -- where they differ, with a graphical tooltip naming both in their
  # colours (WsjrdpTipHelper#wsjrdp_tip).
  def wsjrdp_role_pair(contingent:, jamboree:)
    contingent = contingent.to_s
    jamboree = jamboree.to_s
    roles = (contingent == jamboree) ? [contingent] : [contingent, jamboree]
    # The visible badges first: the first badge of a request brings the
    # stylesheet, which must not end up inside the tooltip's template.
    badges = safe_join(roles.map { |role| wsjrdp_role_badge(role) }, " ")
    tag.span(class: "wsjrdp-role-pair") do
      wsjrdp_tip(badges, lines: [["Rolle im Kontingent", wsjrdp_role_badge(contingent)],
        ["Rolle auf dem Jamboree", wsjrdp_role_badge(jamboree)]])
    end
  end
end
