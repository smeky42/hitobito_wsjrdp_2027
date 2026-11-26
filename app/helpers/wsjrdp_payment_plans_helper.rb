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

  def format_wsjrdp_payment_plan_yme_list(di) = installments_chips(di.yme_list)

  def format_wsjrdp_payment_plan_installments_string(di) = installments_chips(di.yme_list)

  # "2025-12: 300€, 2026-01: 500€"; nil without any installment.
  def installments_text(yme_list)
    return nil if yme_list.blank?

    yme_list.map do |installment|
      year_month = format("%04d-%02d", installment.year, installment.month)
      "#{year_month}: #{format_eur_de(installment.eur, zero_cents: "", space: "")}"
    end.join(", ")
  end

  def installments_table_entries(yme_list)
    total_eur = BigDecimal(0)
    yme_list.to_a.map do |item|
      total_eur += item.eur
      {date: I18n.l(item.to_time_with_zone(day: 5), format: "%b %Y"),
       amount: format_eur_de(item.eur),
       total: format_eur_de(total_eur)}
    end
  end

  def installments_preview_plan_frame_id(plan) = "installments_preview_plan_#{plan.id}"

  def installments_chips(yme_list)
    return tag.span("keine Raten") if yme_list.blank?

    tag.span(class: "d-inline-flex flex-wrap gap-1 align-middle") do
      safe_join(yme_list.map do |item|
        tag.span("#{I18n.l(item.to_time_with_zone(day: 5), format: "%b %Y")} · #{format_eur_de(item.eur, zero_cents: "")}",
          class: "badge bg-white text-body border fw-normal", style: "font-variant-numeric: tabular-nums")
      end)
    end
  end

  def installments_preview_plan(plan_text)
    plan = Wsjrdp2027::InstallmentPlan.from_text(plan_text)
    {items: plan.yme_list, sum_cents: plan.sum_cents}
  rescue Wsjrdp2027::InstallmentPlan::Invalid => e
    {error: e.message}
  end

  def installments_preview_gap_text(sum_cents, fee_cents)
    gap = sum_cents - fee_cents
    if gap.zero?
      "deckt den Beitrag"
    elsif gap.positive?
      "#{cents_in_prose(gap)} mehr als der Beitrag"
    else
      "es fehlen #{cents_in_prose(-gap)}"
    end
  end
end
