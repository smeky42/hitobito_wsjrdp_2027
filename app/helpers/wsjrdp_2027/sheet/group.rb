# frozen_string_literal: true

#  Copyright (c) 2025, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

module Wsjrdp2027::Sheet::Group
  extend ActiveSupport::Concern

  shown_tabs = [
    "global.tabs.info",
    "activerecord.models.person.other",
    "activerecord.models.event.other",
    "activerecord.models.event/course.other",
    "activerecord.models.mailing_list.other",
    "activerecord.models.note.other",
    "groups.tabs.statistics",
    "groups.tabs.logs",
    "groups.tabs.deleted",
    "groups.tabs.map",
    "groups.tabs.finance"
  ]

  included do
    tab "groups.tabs.map",
      :group_map_path,
      if: :show_statistics

    # The whole Finanzen area of a group hangs below this path, so the tab needs
    # no `alt:` for the Buchhaltung's booking page: a tab's own path_method is
    # matched as a PREFIX in the last pass of
    # Wsjrdp2027::Sheet::Base#find_active_tab. The core's Info tab carries
    # `no_alt: true` and therefore does not swallow the match, although
    # "/groups/:id" is a prefix of every group path.
    tab "groups.tabs.finance",
      :group_finance_bookkeeping_path,
      if: :show_finance

    tabs.select! { |t| shown_tabs.include? t.label_key }
    tabs.sort_by! { |t| shown_tabs.index t.label_key }
  end
end
