# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  class Fin::Fees < Base
    # The sheet of Fin::FeesController: the core singularizes the controller
    # name, so "fin/fees" resolves to Sheet::Fin::Fee, not to the area sheet
    # Sheet::Fin::Fees. Declaring the area sheet as its parent puts the
    # overview page back under the area (the index special case of
    # Sheet::Base.sheet_for_controller renders the parent itself) -- see
    # doc/navigation.md.
    class Fin::Fee < Base
      class_attribute :always_render_parent
      self.parent_sheet = Sheet::Fin::Fees
      self.always_render_parent = true

      def title
        I18n.t("fin.nav.fees")
      end
    end
  end
end
