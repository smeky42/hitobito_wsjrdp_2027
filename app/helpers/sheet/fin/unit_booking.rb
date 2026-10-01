# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  class Fin::Reconciliation < Base
    # Sheet of Fin::UnitBookingsController (controller "fin/unit_bookings" ->
    # Sheet::Fin::UnitBooking). Its index renders under the parent
    # Fin::Reconciliation with the area's tabs (Sheet::Base.sheet_for_controller);
    # always_render_parent keeps them on the frame action's direct visit.
    class Fin::UnitBooking < Base
      class_attribute :always_render_parent
      self.parent_sheet = Sheet::Fin::Reconciliation
      self.always_render_parent = true

      def title
        I18n.t("fin.tabs.unit_bookings")
      end
    end
  end
end
