# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Zahlungsverkehr" overview at /fin/payments (default tab): the key figures
# of the orders, debits and returns (Fin::PaymentsOverview). controller
# "fin/payments" -> Sheet::Fin::Payment, under the area sheet
# Sheet::Fin::Payments. See doc/fin/payments.md.
class Fin::PaymentsController < Fin::FinController
  before_action :authorize_action

  def index
    @overview = Fin::PaymentsOverview.new(person_level: can?(:log, WsjrdpFinAccount))
  end

  private

  def authorize_action
    authorize!(:show, WsjrdpFinAccount)
  end
end
