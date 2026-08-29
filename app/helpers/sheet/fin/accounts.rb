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
  # NOT to be confused with Sheet::Fin::Accounting: that is the DIFFERENT area
  # "Buchhaltung" (the DATEV bookkeeping with its master data).
  class Fin::Accounts < Base
    tab "fin.tabs.accounts", :wsjrdp_fin_accounts_path

    def left_nav?
      true
    end

    def render_left_nav
      view.render("fin/left_nav")
    end

    def title
      I18n.t("fin.nav.accounts")
    end
  end
end
