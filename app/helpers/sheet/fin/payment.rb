# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  class Fin::Payments < Base
    # The sheet of Fin::PaymentsController: the core singularizes the
    # controller name, so "fin/payments" resolves to Sheet::Fin::Payment, not to the area sheet
    # Sheet::Fin::Payments; the parent puts the overview back under the area
    # (doc/navigation.md §6).
    class Fin::Payment < Base
      class_attribute :always_render_parent
      self.parent_sheet = Sheet::Fin::Payments
      self.always_render_parent = true

      def title
        I18n.t("fin.nav.payments")
      end
    end
  end
end
