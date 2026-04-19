# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class WsjrdpPaymentPlan < ActiveRecord::Base
  def self.from_parts(wsjrdp_role:, single_payment:, installments:, readonly: true)
    new(wsjrdp_role: wsjrdp_role, single_payment: single_payment).tap do |plan|
      if installments.is_a?(String)
        plan.installments_string = installments
      else
        plan.raw_installments_eur = Wsjrdp2027::PaymentPlanConversionHelper.installments_to_raw_installments_eur(installments)
      end
      plan.readonly! if readonly
    end
  end

  def yme_list
    return [] if raw_installments_eur.blank? || raw_installments_eur.empty?
    Wsjrdp2027::PaymentPlanConversionHelper.year_and_eur_a_to_yme_list(raw_installments_eur[0].to_i, raw_installments_eur[1..])
  end

  def to_ymc_list
    return [] if raw_installments_eur.blank? || raw_installments_eur.empty?
    Wsjrdp2027::PaymentPlanConversionHelper.year_and_eur_a_to_installments_ymc(raw_installments_eur[0].to_i, raw_installments_eur[1..])
  end

  def installments_string
    Wsjrdp2027::PaymentPlanConversionHelper.raw_installments_eur_to_installments_string(raw_installments_eur)
  end

  def installments_string=(value)
    self.raw_installments_eur = Wsjrdp2027::PaymentPlanConversionHelper.installments_string_to_raw_installments_eur(value)
  end

  def total_eur
    if @total_eur.nil?
      @total_eur = if raw_installments_eur.blank? || raw_installments_eur.empty?
        BigDecimal(0)
      else
        raw_installments_eur[1..].sum
      end
    end
    @total_eur
  end

  def total_cents
    (total_eur * BigDecimal(100)).to_i
  end
end
