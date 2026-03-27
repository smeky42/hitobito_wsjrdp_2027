# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::NavigationHelper
  extend ActiveSupport::Concern

  WSJRDP_MAIN_GROUPS = {
    label: :groups,
    url: :groups_path,
    icon_name: "users",
    active_for: %w[groups people fin/ae fin/pn],
    inactive_for: %w[/invoices invoice_articles invoice_config payment_process invoice_lists?]
  }

  WSJRDP_MAIN_FIN = {
    label: :finance,
    url: :fin_path,
    icon_name: "money-bill",
    if: ->(_) { can?(:fin_admin, WsjrdpFinAccount) },
    active_for: %w[fin],
    inactive_for: %w[fin/ae fin/pn people]
  }

  WSJRDP_MAIN_CONTINGENT = {
    label: :contingent,
    url: :contingent_contingent_path,
    icon_name: "campground",
    if: ->(_) { can?(:log, Person) },
    active_for: %w[contingent],
    inactive_for: %w[people]
  }

  included do
    # Remove :invoices tab for the time being. We do not use it and it
    # is visible to people with the :finance permission.
    NavigationHelper::MAIN.delete_if { |e| %i[invoices groups].any?(e[:label]) }
    if NavigationHelper::MAIN.find_index { |e| e[:label] == :groups }.nil?
      NavigationHelper::MAIN.insert(0, WSJRDP_MAIN_GROUPS)
    end
    if NavigationHelper::MAIN.find_index { |e| e[:label] == :finance }.nil?
      NavigationHelper::MAIN.insert(-2, WSJRDP_MAIN_FIN)
    end
    if NavigationHelper::MAIN.find_index { |e| e[:label] == :contingent }.nil?
      NavigationHelper::MAIN.insert(-2, WSJRDP_MAIN_CONTINGENT)
    end
  end
end
