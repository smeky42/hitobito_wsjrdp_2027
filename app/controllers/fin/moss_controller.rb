# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Moss" section overview at /fin/moss (first tab). Empty for now.
# controller "fin/moss" -> Sheet::Fin::Moss (renders the Moss tabs + left_nav).
class Fin::MossController < Fin::FinController
  before_action :authorize_action

  def index
  end

  private

  def authorize_action
    authorize!(:fin_admin, MossBalanceMovement)
  end
end
