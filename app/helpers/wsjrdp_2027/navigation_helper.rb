# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::NavigationHelper
  extend ActiveSupport::Concern

  WSJRDP_MAIN_FIN = {
    label: :finance,
    url: :fin_path,
    icon_name: "money-bill",
    if: ->(_) { can?(:fin_admin, Group.root) },
    active_for: %w[/acc]
  }

  included do
    # Remove :invoices tab for the time being. We do not use it and it
    # is visible to people with the :finance permission.
    NavigationHelper::MAIN.delete_if { |e| e[:label] == :invoices }
    if NavigationHelper::MAIN.find_index { |e| e[:label] == :finance }.nil?
      NavigationHelper::MAIN.insert(-2, WSJRDP_MAIN_FIN)
    end
  end
end
