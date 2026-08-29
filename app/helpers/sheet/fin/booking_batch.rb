# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  class Fin::Accounting < Base
    class Fin::BookingBatch < Base
      class_attribute :always_render_parent
      self.parent_sheet = Sheet::Fin::Accounting
      self.always_render_parent = true

      def title
        "WSJRDP Buchungsstapel"
      end
    end
  end
end
