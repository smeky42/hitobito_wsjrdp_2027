# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module WsjrdpPaymentPlansHelper
  include ContractHelper

  def format_wsjrdp_payment_plan_single_payment(di)
    di.single_payment ? "Ja" : "Nein"
  end

  def format_wsjrdp_payment_plan_total_eur(di)
    format_eur_de(di.total_eur, zero_cents: "")
  end

  def format_wsjrdp_payment_plan_yme_list(di)
    installments = di.yme_list
    if installments.blank?
      content_tag(:span, "(keine)", class: "muted")
    else
      installments.map do |installment|
        month_year = I18n.l(installment.to_time_with_zone(day: 5), format: "%b") + " #{installment.year}"
        eur = format_eur_de(installment.eur, zero_cents: "")
        "#{month_year}: #{eur}"
      end.join(", ")
    end
  end
end
