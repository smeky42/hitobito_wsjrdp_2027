# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::NavigationHelper
  extend ActiveSupport::Concern

  WSJRDP_MAIN = [ # rubocop:disable Style/MutableConstant extended in wagons
    {label: :groups,
     url: :groups_path,
     icon_name: "users",
     active_for: %w[groups people],
     inactive_for: %w[/invoices invoice_articles invoice_config payment_process invoice_lists?]},

    {label: :events,
     url: :list_events_path,
     icon_name: "calendar-alt",
     active_for: %w[list_events],
     if: ->(_) { can?(:list_available, Event) }},

    {label: :courses,
     url: :list_courses_path,
     icon_name: "book",
     active_for: %w[list_courses],
     if: ->(_) { Group.course_types.present? && can?(:list_available, Event::Course) }},

    # {label: :invoices,
    #  url: :first_group_invoices_or_root_path,
    #  icon_name: "money-bill-alt",
    #  if: ->(_) { current_user.finance_groups.any? },
    #  active_for: %w[/invoices
    #    invoices/evaluations
    #    invoices/by_article
    #    invoice_articles
    #    invoice_config
    #    payment_process
    #    invoice_lists?]},

    {label: :admin,
     url: :label_formats_path,
     icon_name: "cog",
     active_for: %w[self_registration_reasons
       label_formats
       custom_contents
       event_kinds
       event_kind_categories
       qualification_kinds
       oauth/applications
       help_texts
       oauth/active_authorizations
       event_feed
       tags
       hitobito_log_entries
       mails/imap mails/bounces
       api],
     if: ->(_) { can?(:index, LabelFormat) }}
  ]

  included do
    NavigationHelper::MAIN = WSJRDP_MAIN
  end
end
