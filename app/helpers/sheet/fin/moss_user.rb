# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  class Fin::Moss < Base
    # Sheet of Fin::MossUsersController. The list falls back to the parent
    # Fin::Moss; the record's page keeps the Moss tabs (always_render_parent).
    class Fin::MossUser < Base
      class_attribute :always_render_parent
      self.parent_sheet = Sheet::Fin::Moss
      self.always_render_parent = true

      def title
        I18n.t("fin.tabs.moss_users")
      end
    end
  end
end
