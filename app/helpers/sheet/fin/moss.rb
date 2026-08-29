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
  # transactions list and the four kind tabs, which are the same list pinned to
  # one kind (Fin::MossTransactionsController, route default `kind`). This is
  # also the sheet of Fin::MossController (controller "fin/moss" ->
  # Sheet::Fin::Moss), so /fin/moss renders the tabs directly. See
  # doc/navigation.md.
  class Fin::Moss < Base
    # Übersicht is an exact-match tab (no_alt) so it does not also light up on the
    # /fin/moss/transactions sub-paths.
    tab "fin.tabs.overview", :moss_path, no_alt: true
    tab "fin.tabs.transactions", :moss_transactions_path
    # Tab order = the order of the overview's kind cards
    # (Fin::MossTransactionsController::KIND_TABS).
    #
    # The four kind tabs show the kind's icon in front of the word, so their
    # label is not an i18n key but a SYMBOL: the core then calls the helper
    # method of that name and renders its html_safe result inside the link
    # (Sheet::Tab::Renderer#label, doc/navigation.md §5). The methods live in
    # Fin::MossTransactionsHelper and read the words from the same
    # fin.tabs.<slug> keys as before. The /fin quick links, which reuse
    # renderer.label, therefore carry the icons too.
    tab :moss_card_transactions_tab_label, :moss_card_transactions_path
    tab :moss_reimbursements_tab_label, :moss_reimbursements_path
    tab :moss_invoices_tab_label, :moss_invoices_path
    tab :moss_top_ups_tab_label, :moss_top_ups_path

    def left_nav?
      true
    end

    def render_left_nav
      view.render("fin/left_nav")
    end

    def title
      I18n.t("fin.nav.moss")
    end
  end
end
