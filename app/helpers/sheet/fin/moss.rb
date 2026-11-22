# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  # "Moss" -- the third sub-item of the Finanzen main-nav section (between
  # Beiträge and Buchhaltung). Holds the Moss overview (default tab), the
  # transactions list, then the users, teams and departments
  # (Fin::MossOrganisationController). This is also the sheet of
  # Fin::MossController (controller "fin/moss" -> Sheet::Fin::Moss), so
  # /fin/moss renders the tabs directly. See doc/navigation.md.
  #
  # On the transactions pages a second tab bar follows: "Alle" and the four
  # kind tabs, which are the same list pinned to one kind
  # (Fin::MossTransactionsController, route default `kind`). They are not tabs
  # of the sheet, so the /fin quick links leave them out.
  class Fin::Moss < Base
    # Übersicht is an exact-match tab (no_alt) so it does not also light up on the
    # /fin/moss/transactions sub-paths.
    tab "fin.tabs.overview", :moss_path, no_alt: true
    tab "fin.tabs.transactions", :moss_transactions_path
    # The organisation in Moss (Fin::MossOrganisationController).
    # From the audit tier up (Wsjrdp2027::FinanceAccess.moss_organisation_models).
    tab "fin.tabs.moss_users", :moss_users_path, if: ->(view, *) { view.can?(:show, MossUser) }
    tab "fin.tabs.moss_teams", :moss_teams_path, if: ->(view, *) { view.can?(:show, MossTeam) }
    tab "fin.tabs.moss_departments", :moss_departments_path, if: ->(view, *) { view.can?(:show, MossDepartment) }

    def left_nav?
      true
    end

    def render_left_nav
      view.render("fin/left_nav")
    end

    def title
      I18n.t("fin.nav.moss")
    end

    def render_tabs
      main_tabs = super
      return main_tabs unless transactions_page?

      safe_join([main_tabs, render_kind_tabs])
    end

    private

    # The list and the page of one transaction (Fin::MossTransactionsController).
    def transactions_page?
      view.controller_path == "fin/moss_transactions"
    end

    # On a kind tab the main bar's "Transaktionen" stays lit.
    def find_active_tab
      return super unless transactions_page?

      visible_tabs.detect { |tab| tab.path_method == :moss_transactions_path } || super
    end

    # "Alle" and one tab per kind, in the order of
    # Fin::MossTransactionsController::KIND_TABS. The page of one transaction
    # lights the tab of its kind.
    def render_kind_tabs
      kinds = [nil] + ::Fin::MossTransactionsController::KIND_TABS.keys
      content_tag(:ul, class: "nav nav-sub fin-moss-kind-tabs") do
        safe_join(kinds) do |kind|
          label = kind ? view.moss_kind_tab_label_with_icon(kind) : I18n.t("fin.tabs.moss_all")
          path = kind ? view.moss_kind_tab_path(kind) : view.moss_transactions_path
          content_tag(:li, link_to(label, path), class: (kind == current_kind) ? "active" : nil)
        end
      end
    end

    # The kind of the shown list, or of the shown transaction; nil on "Alle".
    def current_kind
      view.instance_variable_get(:@transaction)&.type || view.current_kind
    end
  end
end
