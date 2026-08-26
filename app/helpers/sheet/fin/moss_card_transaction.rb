# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  class Fin::Moss < Base
    # Sheet of Fin::MossCardTransactionsController (controller
    # "fin/moss_card_transactions" -> Sheet::Fin::MossCardTransaction). Only the
    # show/detail page uses it directly; the index action falls back to the
    # parent Fin::Moss (Sheet::Base.sheet_for_controller). always_render_parent
    # keeps the Moss tabs + left_nav visible on the detail page.
    class Fin::MossCardTransaction < Base
      class_attribute :always_render_parent
      self.parent_sheet = Sheet::Fin::Moss
      self.always_render_parent = true

      def title
        I18n.t("fin.tabs.card_transactions")
      end
    end
  end
end
