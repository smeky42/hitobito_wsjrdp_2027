module Wsjrdp2027::Sheet::Base
  private

  # if current_page matches, this tab is active
  # if alt_paths matches exactly, this tab is active
  # if alt_paths prefix matches, this tab is active
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
      active = visible_tabs.detect { |tab| tab.alt_path_of?(current_path) }
    end
    active || visible_tabs.first
  end
end
