# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A standard installment plan. Plans are soft-deleted only (deleted_at): fee
# rules and people may refer to them, and a deleted plan stays as it was --
# destroy sets deleted_at, delete refuses, a deleted plan is read-only. The
# plans in effect are .kept; the database keeps one of them per role, single
# payment and payment method.
class WsjrdpPaymentPlan < ActiveRecord::Base
  scope :kept, -> { where(deleted_at: nil) }

  # additional_info is never NULL (database default {}); nil stands for {}.
  before_validation { self.additional_info ||= {} }

  def deleted? = deleted_at_in_database.present?

  def readonly? = super || deleted?

  # Soft-deletes the plan. Answers self, like ActiveRecord's destroy.
  def destroy
    update!(deleted_at: Time.zone.now) unless deleted?
    self
  end

  def destroy! = destroy

  def delete
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} is soft-deleted only (destroy)"
  end

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

  def payment_method_display = Wsjrdp2027::ParticipationFee.payment_method_label(payment_method)

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
