# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# THE colours of the contingent's roles (WSJ role and contingent role alike),
# one place for every page that colours a role (WsjrdpRoleBadgeHelper). A role
# area shares one hue; within it the stronger shade marks the leading role:
#
#   participants  YP, UL                teal
#   JPT           JPT                   sky
#   staff         IST, BMT, Food-House  violet to fuchsia
#   CMT           CMT                   orange
#   external      EXT, unknown          grey
#
# Red, yellow and green stay free: in the finance pages they mean error,
# warning and ok. Each role has a background and a text colour; two reserve
# pairs wait for further roles.
module Wsjrdp2027::RoleColors
  Pair = Data.define(:background, :text)

  COLORS = {
    "YP" => Pair.new("#CCFBF1", "#115E59"),
    "UL" => Pair.new("#5EEAD4", "#134E4A"),
    "JPT" => Pair.new("#E0F2FE", "#075985"),
    "IST" => Pair.new("#EDE9FE", "#5B21B6"),
    "BMT" => Pair.new("#C4B5FD", "#4C1D95"),
    "FOOD" => Pair.new("#F5D0FE", "#86198F"),
    "CMT" => Pair.new("#FED7AA", "#7C2D12"),
    "EXT" => Pair.new("#F1F5F9", "#334155")
  }.freeze

  RESERVE = [Pair.new("#FFE4E6", "#9F1239"), Pair.new("#ECFCCB", "#3F6212")].freeze

  # The key of a role's colour: its short name ("JPT / JDT" -> "JPT"), EXT for
  # anything unknown ("???", blank).
  def self.key_for(role)
    key = role.to_s.split(%r{\s*/\s*}).first.to_s.strip.upcase
    COLORS.key?(key) ? key : "EXT"
  end

  def self.css_class(role) = "wsjrdp-role-#{key_for(role).downcase}"

  # The stylesheet of all role classes.
  def self.css
    COLORS.map { |key, pair|
      ".wsjrdp-role-#{key.downcase} { background-color: #{pair.background}; color: #{pair.text}; }"
    }.join("\n")
  end
end
