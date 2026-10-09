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
  # Two tabs: Übersicht (the account list at /fin/acc) and Konten. The account
  # and transaction pages render this sheet (always_render_parent); there the
  # Konten tab is active and a second tab bar lists the accounts with a tab of
  # their own (WsjrdpFinAccount.tab_visible), the page's account active.
  #
  # NOT to be confused with Sheet::Fin::Accounting: that is the DIFFERENT area
  # "Buchhaltung" (the DATEV bookkeeping with its master data).
  class Fin::Accounts < Base
    # Übersicht is an exact-match tab (no_alt) so it does not also light up on
    # the account pages below /fin/acc.
    tab "fin.tabs.overview", :wsjrdp_fin_accounts_path, no_alt: true
    tab "fin.tabs.accounts", :fin_accounts_tab_path,
      if: ->(view, *) { view.fin_tab_accounts.any? }

    def left_nav?
      true
    end

    def render_left_nav
      view.render("fin/left_nav")
    end

    def title
      I18n.t("fin.nav.accounts")
    end

    def render_tabs
      main_tabs = super
      return main_tabs unless current_account

      safe_join([main_tabs, render_account_tabs])
    end

    private

    # The account of an account page or of a transaction page; nil elsewhere.
    def current_account
      view.instance_variable_get(:@wsjrdp_fin_account) ||
        view.instance_variable_get(:@wsjrdp_camt_transaction)&.fin_account
    end

    def find_active_tab
      return super unless current_account

      visible_tabs.detect { |tab| tab.path_method == :fin_accounts_tab_path } || super
    end

    # The page's own account always gets a tab, even when the rule would leave
    # it out (a closed or hidden account reached by link).
    def render_account_tabs
      accounts = view.fin_tab_accounts
      accounts += [current_account] unless accounts.include?(current_account)
      content_tag(:ul, class: "nav nav-sub fin-account-tabs") do
        safe_join(accounts) do |account|
          content_tag(:li,
            link_to(view.fin_account_label(account), view.wsjrdp_fin_account_path(account)),
            class: (account == current_account) ? "active" : nil)
        end
      end
    end
  end
end
