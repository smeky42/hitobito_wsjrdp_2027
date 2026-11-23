# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  class Fin::Moss < Base
    # Sheet of Fin::MossExpensesController (controller "fin/moss_expenses" ->
    # Sheet::Fin::MossExpense), an expense's own page. always_render_parent
    # keeps the Moss tabs + left_nav visible on it; the Transaktionen tab and
    # the tab of the expense's kind stand lit (Sheet::Fin::Moss).
    class Fin::MossExpense < Base
      class_attribute :always_render_parent
      self.parent_sheet = Sheet::Fin::Moss
      self.always_render_parent = true

      def title
        "Moss Ausgabe #{entry.id}"
      end
    end
  end
end
