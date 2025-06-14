# frozen_string_literal: true

module Wsjrdp2027::Sheet::Person
  extend ActiveSupport::Concern

  # Only these tabs can be shown, in this order.
  shown_tabs = [
    "global.tabs.info",
    "people.tabs.medicine",
    # "people.tabs.subscriptions",
    "people.tabs.print",
    "people.tabs.upload",
    "people.tabs.invoices",
    # "activerecord.models.message.other",
    "people.tabs.history",
    "people.tabs.log",
    "people.tabs.security_tools",
    "people.tabs.colleagues",
    "activerecord.models.assignment.other"
  ]

  included do  
    tab "people.tabs.print",
      :print_group_person_path,
      if: :show

    self.tabs.select! { |t| shown_tabs.include? t.label_key }
    self.tabs.sort_by! { |t| shown_tabs.index t.label_key }
  end
end
