# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::Sheet::Base
  private

  # if current_page matches, this tab is active
  # if alt_paths matches exactly, this tab is active
  # if alt_paths prefix matches, the tab with the longest matching path is
  #   active -- the most specific: /people/:id (Info) starts
  #   /people/:id/status/primary_role too, which is the status tab's
  # if nothing matches, first tab is active
  def find_active_tab
    active = visible_tabs.detect(&:current_page?)

    if active.nil?
      current_path = current_nav_path
      active = visible_tabs.detect do |tab|
        tab.alt_paths.any? { |p| current_path =~ %r{^/?#{tab.send(:path_for, p)}/?$} }
      end
    end
    if active.nil?
      current_path = current_nav_path
      matches = visible_tabs.filter_map do |tab|
        lengths = tab.alt_paths.map { |p| tab.send(:path_for, p) }
          .select { |path| current_path =~ %r{/?#{path}/?} }.map(&:length)
        [tab, lengths.max] if lengths.any?
      end
      # max_by keeps the first of equally long matches: the tabs' order.
      active = matches.max_by { |_tab, length| length }&.first
    end
    active || visible_tabs.first
  end
end
