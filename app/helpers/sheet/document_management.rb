# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  # "Dokumentenverwaltung" in Einstellungen, for admins (:manage_documents on
  # WsjrdpDocument): the overview (/document_management) and registering the
  # registration uploads (/document_management/registration_documents). The
  # left nav is the one of Einstellungen (Sheet::Admin). The documents
  # themselves and their kinds are the main section Dokumente
  # (Sheet::Documents).
  class DocumentManagement < Admin
    # no_alt: its path is the prefix of the other tab's path, so it would
    # count as active on its pages.
    tab "document_management.tabs.overview", :document_management_path, no_alt: true,
      if: ->(view, *) { view.can?(:manage_documents, WsjrdpDocument) }
    tab "document_management.tabs.registration_documents", :document_management_registration_documents_path,
      if: ->(view, *) { view.can?(:manage_documents, WsjrdpDocument) }

    def title
      I18n.t("document_management.title")
    end

    # The sheets of the tabs' controllers, under their area sheet like
    # Sheet::Fin::PaymentReference.
    class RegistrationDocument < Admin
      class_attribute :always_render_parent
      self.parent_sheet = Sheet::DocumentManagement
      self.always_render_parent = true

      def title
        I18n.t("document_management.tabs.registration_documents")
      end
    end

    # A tab of the main section Dokumente (Sheet::Documents), which has no
    # left nav.
    class DocumentsTab < Base
      class_attribute :always_render_parent
      self.always_render_parent = true

      def left_nav? = false
    end

    class Document < DocumentsTab
      def title
        I18n.t("document_management.tabs.documents")
      end
    end

    class DocumentGroup < DocumentsTab
      def title
        I18n.t("document_management.tabs.document_groups")
      end
    end

    class DocumentKind < DocumentsTab
      def title
        I18n.t("document_management.tabs.document_kinds")
      end
    end
  end

  # The main section Dokumente (Wsjrdp2027::NavigationHelper), for admins:
  # Alle, every document (/documents); Nach Person und Art, one row per
  # person and kind (/documents/by_person_and_kind); Arten, the kinds of
  # document (/document_management/document_kinds). The tabs are its only
  # navigation; the section has no left nav.
  class Documents < Base
    # Alle is also active on a document's page (/documents/:id/details), Nach
    # Person und Art on a group's page (find_active_tab).
    tab "document_management.tabs.documents", :document_management_documents_path,
      if: ->(view, *) { view.can?(:manage_documents, WsjrdpDocument) }
    tab "document_management.tabs.document_groups", :document_management_document_groups_path,
      if: ->(view, *) { view.can?(:manage_documents, WsjrdpDocument) }
    tab "document_management.tabs.document_kinds", :document_management_document_kinds_path,
      if: ->(view, *) { view.can?(:manage_documents, WsjrdpDocument) }

    def title
      I18n.t("document_management.documents_title")
    end

    def left_nav? = false

    # The tabs on every page of the section, the form of a new kind (new,
    # create) included -- the core leaves them out there.
    def render_main_tabs = render_tabs

    private

    # Of the tabs whose path starts the current one, the most specific wins:
    # a group's page (/documents/by_person_and_kind/:id) starts with the paths
    # of Alle and Nach Person und Art both.
    def find_active_tab
      visible_tabs.detect(&:current_page?) ||
        visible_tabs.select { |tab| tab.alt_path_of?(current_nav_path) }.max_by { |tab| tab.path.length } ||
        visible_tabs.first
    end
  end

  DocumentManagement::DocumentsTab.parent_sheet = Documents
end
