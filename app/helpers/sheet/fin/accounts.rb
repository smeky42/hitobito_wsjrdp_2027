# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  # "Konten & Wallets" -- the first sub-item of the Finanzen main-nav section:
  # the WSJRDP money accounts (the bank accounts and the Moss wallet), each
  # account's statement (/fin/acc/:id) and the camt transactions behind it
  # (/fin/tx/:id).
  #
  # Three tabs: Übersicht (the account list at /fin/acc), Konten and Umbuchungen
  # (/fin/acc/internal_transfers, Fin::InternalTransfersController). Under the
  # accounts tab a second tab bar: all transactions (/fin/acc/all, where that
  # tab leads), then the accounts with a tab of their own
  # (WsjrdpFinAccount.tab_visible). The account and transaction pages render
  # this sheet (always_render_parent), their account's tab active.
  #
  # NOT to be confused with Sheet::Fin::Accounting: that is the DIFFERENT area
  # "Buchhaltung" (the DATEV bookkeeping with its master data).
  class Fin::Accounts < Base
    # Übersicht is an exact-match tab (no_alt) so it does not also light up on
    # the account pages below /fin/acc.
    tab "fin.tabs.overview", :wsjrdp_fin_accounts_path, no_alt: true
    tab "fin.tabs.accounts", :fin_accounts_tab_path
    tab "fin.tabs.internal_transfers", :internal_transfers_path

    def left_nav?
      true
    end

    def render_left_nav
      view.render("fin/left_nav")
    end

    def title
      I18n.t("fin.nav.accounts")
    end

    # The core leaves the tabs out on new/create (meant for the sheet of one
    # record); this section keeps them, so "Neue Umbuchung" still shows where
    # it belongs and how to get back.
    def render_main_tabs
      render_tabs
    end

    def render_tabs
      main_tabs = super
      return main_tabs unless current_account || all_page?

      safe_join([main_tabs, render_account_tabs])
    end

    private

    # The account of an account page or of a transaction page; nil elsewhere.
    def current_account
      view.instance_variable_get(:@wsjrdp_fin_account) ||
        view.instance_variable_get(:@wsjrdp_camt_transaction)&.fin_account
    end

    # The all-transactions page (Fin::AccountTransactionsController).
    def all_page? = view.controller_path == "fin/account_transactions"

    def find_active_tab
      return super unless current_account || all_page?

      visible_tabs.detect { |tab| tab.path_method == :fin_accounts_tab_path } || super
    end

    # The page's own account always gets a tab, even when the rule would leave
    # it out (a closed or hidden account reached by link).
    def render_account_tabs
      accounts = view.fin_tab_accounts
      accounts += [current_account] unless current_account.nil? || accounts.include?(current_account)
      all = content_tag(:li, link_to(I18n.t("fin.tabs.all"), view.fin_account_transactions_path),
        class: all_page? ? "active" : nil)
      content_tag(:ul, class: "nav nav-sub fin-account-tabs") do
        safe_join([all] + accounts.map do |account|
          content_tag(:li,
            link_to(view.fin_account_label(account), view.wsjrdp_fin_account_path(account)),
            class: (account == current_account) ? "active" : nil)
        end)
      end
    end
  end
end
