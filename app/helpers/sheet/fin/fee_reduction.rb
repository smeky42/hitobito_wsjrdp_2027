# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  class Fin::Fees < Base
    # The sheet of Fin::FeeReductionsController ("fin/fee_reductions" singularizes
    # to Sheet::Fin::FeeReduction): the Reduktionen tab under the Beiträge area.
    class Fin::FeeReduction < Base
      class_attribute :always_render_parent
      self.parent_sheet = Sheet::Fin::Fees
      self.always_render_parent = true

      def title
        "Beitragsreduktionen"
      end
    end
  end
end
