# frozen_string_literal: true

module Wsjrdp2027::Sheet::Person
  extend ActiveSupport::Concern

  # Only these tabs can be shown, in this order.
  shown_tabs = [
    "global.tabs.info",
    "people.tabs.medical",
    "people.tabs.jamboree_data",
    "people.tabs.finance",
    # "people.tabs.invoices",  # 2026-01-03 - no invoices in Hitobito at the moment
    # "people.tabs.subscriptions",
    "people.tabs.print",
    "people.tabs.upload",
    # "activerecord.models.message.other",
    "people.tabs.history",
    "people.tabs.log",
    "people.tabs.status",
    "people.tabs.unit",
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

    tab "people.tabs.finance",
      :person_fee_path_with_group,
      alt: [
        :accounting_group_person_path,
        :person_accounting_path_with_group,
        :person_finance_path_with_group,
        :person_spend_path_with_group,
        :person_deregistration_path_with_group,
        # The same pages in the URL of the primary group.
        :fee_group_person_path,
        :finance_group_person_path,
        :spend_group_person_path,
        :deregistration_group_person_path
      ],
      # Also the finance audit tier, which reads the Beitrag page only
      # (PersonFinancePagesHelper).
      if: ->(view, *path_args) { view.person_finance_tab_visible?(path_args.last) }

    tab "people.tabs.medical",
      :medical_group_person_path,
      alt: [:medical_edit_group_person_path],
      if: :show

    tab "people.tabs.jamboree_data",
      :jamboree_data_tab_path,
      # Both URLs of the page and its edit form are this tab.
      alt: [:jamboree_data_group_person_path, :jamboree_data_person_path_with_group,
        :jamboree_data_edit_group_person_path],
      if: :show

    tab "people.tabs.status",
      :status_tab_path,
      # Both URLs of the page and its edit form are this tab.
      alt: [:status_group_person_path, :status_person_path_with_group, :status_edit_group_person_path],
      if: (lambda do |view, _group, person|
        view.can?(:log, person)
      end)

    tab "people.tabs.unit",
      :unit_group_person_path,
      if: (lambda do |view, _group, person|
        view.can?(:log, person)
      end)

    self.tabs.select! { |t| shown_tabs.include? t.label_key }
    self.tabs.sort_by! { |t| shown_tabs.index t.label_key }

    def current_parent_nav_path
      current? ? request.path : child.current_parent_nav_path
    end
  end
end
