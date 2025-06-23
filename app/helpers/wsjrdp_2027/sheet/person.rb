# frozen_string_literal: true

module Wsjrdp2027::Sheet::Person
  extend ActiveSupport::Concern

  # Only these tabs can be shown, in this order.
  shown_tabs = [
    "global.tabs.info",
    "people.tabs.medical",
    # "people.tabs.subscriptions",
    "people.tabs.print",
    "people.tabs.upload",
    "people.tabs.invoices",
    # "activerecord.models.message.other",
    "people.tabs.history",
    "people.tabs.log",
    "people.tabs.status",
    "people.tabs.security_tools",
    "people.tabs.colleagues",
    "activerecord.models.assignment.other"
  ]

  included do
    tab "people.tabs.print",
      :print_group_person_path,
      if: :show

    tab "people.tabs.upload",
      :upload_group_person_path,
      if: :show

    tab "people.tabs.medical",
      :medical_group_person_path,
      alt: [:medical_edit_group_person_path],
      if: :show

    tab "people.tabs.status",
      :status_group_person_path,
      alt: [:status_edit_group_person_path],
      if: (lambda do |view, _group, person|
        view.can?(:log, person)
      end)

    self.tabs.select! { |t| shown_tabs.include? t.label_key }
    self.tabs.sort_by! { |t| shown_tabs.index t.label_key }
  end
end
