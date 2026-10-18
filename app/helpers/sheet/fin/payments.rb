# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  # "Zahlungsverkehr" -- the second sub-item of the Finanzen main-nav section,
  # right after Konten & Wallets, whose accounts the orders are sent from: the
  # overview (/fin/payments), the orders (SEPA files, /fin/payments/orders),
  # the Sammler of the direct debit orders (/fin/direct_debit_payment_infos),
  # the debits (/fin/payments/debits) and the returns
  # (/fin/payments/returns). See doc/fin/payments.md.
  #
  # The orders and the Sammler name nobody; the debits and the returns are person-level
  # payment data, so their tabs show only with :log on WsjrdpFinAccount, as
  # the Personen tab of Beiträge.
  class Fin::Payments < Base
    # Übersicht is an exact-match tab (no_alt) so it does not also light up on
    # the /fin/payments/... sub-paths.
    tab "fin.tabs.overview", :fin_payments_path, no_alt: true
    tab "fin.tabs.payment_orders", :payment_orders_path
    tab "fin.tabs.direct_debit_payment_infos", :direct_debit_payment_infos_path
    tab "fin.tabs.direct_debits", :direct_debits_path,
      if: ->(view, *) { view.can?(:log, WsjrdpFinAccount) }
    tab "fin.tabs.payment_returns", :payment_returns_path,
      if: ->(view, *) { view.can?(:log, WsjrdpFinAccount) }

    def left_nav?
      true
    end

    def render_left_nav
      view.render("fin/left_nav")
    end

    def title
      I18n.t("fin.nav.payments")
    end
  end
end
