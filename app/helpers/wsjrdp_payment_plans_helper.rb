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
    installments_text(di.yme_list) || content_tag(:span, "(keine)", class: "muted")
  end

  # An installment plan written out, each month as ISO year-month, e.g.
  # "2025-12: 300€, 2026-01: 500€, 2026-02: 312,50€"; months without an
  # installment are left out. nil without any installment.
  # The one place a plan is written this way: the payment plans list, the
  # Ratenplan line of the status page, the Ratenplan section of the Beitrag
  # page, the person log.
  def installments_text(yme_list)
    return nil if yme_list.blank?

    yme_list.map do |installment|
      year_month = format("%04d-%02d", installment.year, installment.month)
      "#{year_month}: #{format_eur_de(installment.eur, zero_cents: "", space: "")}"
    end.join(", ")
  end
end
