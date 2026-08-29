# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Beiträge" section overview at /fin/fees (the area's Übersicht tab). The page
# names the area and links its two lists; the lists themselves are
# Fin::WsjrdpFinPersonFeesController and Fin::WsjrdpPaymentPlansController.
# controller "fin/fees" -> Sheet::Fin::Fees (renders the left_nav + the tabs).
class Fin::FeesController < Fin::FinController
  before_action :authorize_action

  def index
  end

  private

  def authorize_action
    authorize!(:fin_admin, WsjrdpFinAccount)
  end
end
