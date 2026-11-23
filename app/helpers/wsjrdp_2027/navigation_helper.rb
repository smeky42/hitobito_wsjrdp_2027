# frozen_string_literal: true

#  Copyright (c) 2025, 2026 German Contingent for the World Scout Jamboree 2027.
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
    active_for: %w[groups /people fin/ae fin/pn],
    # fin/admin: the Verwaltung page /fin/admin/finance_groups carries the
    # fragment "groups" in its path and belongs to the Finanzen section.
    inactive_for: %w[/invoices invoice_articles invoice_config payment_process invoice_lists? fin/admin]
  }

  WSJRDP_MAIN_FIN = {
    label: :finance,
    url: :fin_path,
    icon_name: "money-bill",
    # Read tier and up (:show), so a finance auditor reaches the section at all
    if: ->(_) { can?(:show, WsjrdpFinAccount) },
    # Every finance page lives under /fin, so one fragment covers them all.
    active_for: %w[fin],
    inactive_for: %w[fin/ae fin/pn /people]
  }

  # The documents and their kinds (Sheet::Documents), for admins: /documents
  # and /document_management/document_kinds. The rest of /document_management
  # belongs to Einstellungen (shared/_admin_nav_main_wsjrdp_2027); the
  # fragment "documents" would match its registration_documents too.
  WSJRDP_MAIN_DOCUMENTS = {
    label: :documents,
    url: :document_management_documents_path,
    icon_name: "file-alt",
    if: ->(_) { can?(:manage_documents, WsjrdpDocument) },
    active_for: %w[documents document_management/document_kinds],
    inactive_for: %w[registration_documents]
  }

  WSJRDP_MAIN_CONTINGENT = {
    label: :contingent,
    url: :contingent_contingent_path,
    icon_name: "campground",
    if: ->(_) { can?(:show_wsjrdp_contingent, Group.root) },
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
    if NavigationHelper::MAIN.find_index { |e| e[:label] == :documents }.nil?
      NavigationHelper::MAIN.insert(-2, WSJRDP_MAIN_DOCUMENTS)
    end
    if NavigationHelper::MAIN.find_index { |e| e[:label] == :contingent }.nil?
      NavigationHelper::MAIN.insert(-2, WSJRDP_MAIN_CONTINGENT)
    end
    # The credential pages belong to the settings only, even when an
    # account name looks like another section (e.g. "finanzen" holds "fin").
    NavigationHelper::MAIN.each do |entry|
      entry[:inactive_for] = Array(entry[:inactive_for]) | %w[credentials] unless entry[:label] == :admin
    end
    # The settings also cover the country codes and credentials pages.
    admin = NavigationHelper::MAIN.find { |e| e[:label] == :admin }
    admin[:active_for] = admin[:active_for] | %w[country_codes credentials] if admin
    # And for the Dokumentenverwaltung, apart from the kinds of document,
    # which belong to the main section Dokumente. Not for /fin/sync/moss_api,
    # although the core's fragment "api" matches it.
    if admin
      admin[:active_for] = admin[:active_for] | %w[document_management]
      admin[:inactive_for] = Array(admin[:inactive_for]) | %w[document_kinds fin/sync]
    end
  end
end
