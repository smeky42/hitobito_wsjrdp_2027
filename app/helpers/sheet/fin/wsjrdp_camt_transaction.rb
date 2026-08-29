# frozen_string_literal: true

#  Copyright (c) 2025, 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  class Fin::Accounts < Base
    # The single camt transaction of an account statement (/fin/tx/:id). It
    # belongs to the "Konten & Wallets" area, so it hangs under that sheet and
    # renders its left_nav + tabs (always_render_parent).
    class Fin::WsjrdpCamtTransaction < Base
      class_attribute :always_render_parent
      self.parent_sheet = Sheet::Fin::Accounts
      self.always_render_parent = true

      def title
        "Konto-Transaktion #{entry.id}"
      end
    end
  end
end
