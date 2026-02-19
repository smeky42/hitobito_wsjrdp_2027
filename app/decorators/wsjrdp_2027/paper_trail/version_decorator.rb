# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::PaperTrail::VersionDecorator
  def t_event(user: nil, item: nil, object_changes: nil, object_name: nil)
    if %w[wsjrdp_add_tag wsjrdp_remove_tag].include?(event) && object_changes.present?
      tag_change = YAML.load(object_changes, permitted_classes: [Date, Time, Symbol])["tag"] || [nil, nil]
      tag_name = ERB::Util.html_escape(tag_change&.[]((event == "wsjrdp_add_tag") ? 1 : 0))
      I18n.t(
        "version.#{event}",
        user: user,
        item: item,
        object_name: object_name,
        object_changes: object_changes,
        tag_name: tag_name
      ).html_safe
    else
      I18n.t(
        "version.#{event}",
        user: user,
        item: item,
        object_name: object_name,
        object_changes: object_changes
      )
    end
  end
end
