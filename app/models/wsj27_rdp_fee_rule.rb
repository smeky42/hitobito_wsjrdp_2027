# frozen_string_literal: true

class Wsj27RdpFeeRule < ActiveRecord::Base
  include ContractHelper
  include WsjrdpInstallmentsHelper

  # rubocop:disable Rails/InverseOf
  belongs_to :person, foreign_key: :people_id, optional: true, class_name: "Person"
  belongs_to :custom_installments_payment_plan, optional: true, class_name: "WsjrdpPaymentPlan"
  # Who created the rule (planned), changed it last, activated it and deleted
  # it (replaced by a newly activated rule, or a plan discarded); nil for the
  # rules from before these were recorded.
  belongs_to :created_by, optional: true, class_name: "Person"
  belongs_to :updated_by, optional: true, class_name: "Person"
  belongs_to :activated_by, optional: true, class_name: "Person"
  belongs_to :deleted_by, optional: true, class_name: "Person"
  # rubocop:enable Rails/InverseOf

  # The rules that carry a plan of their own (a starting year and the monthly
  # amounts), as opposed to a reduction alone.
  scope :with_plan, -> { where.not(custom_installments_starting_year: nil).where.not(custom_installments_cents: nil) }

  # The payment method goes with the plan: present exactly when a plan is,
  # direct debit unless chosen otherwise (the database checks the same).
  before_validation :_normalize_custom_installments_payment_method
  # additional_info is never NULL (database default {}); nil stands for {}.
  before_validation { self.additional_info ||= {} }

  def soft_delete!(by: nil)
    self.deleted_at = Time.zone.now
    self.status = "deleted"
    self.deleted_by = by if by
    save!
  end

  def activate!(prev_rule_id = nil, by: nil)
    self.activated_at = Time.zone.now
    self.status = "active"
    if prev_rule_id
      self.prev_rule_id = prev_rule_id
    end
    self.activated_by = by if by
    save!
  end

  # The plan written as "starting year: amount; amount; ..." from January --
  # what the plan's form takes (custom_installments_string=): the year, a
  # colon, then the euros of each month, separated by semicolons; "," or "."
  # before the cents.
  CUSTOM_INSTALLMENTS_STRING_FORMAT = /\A\s*\d{4}\s*:\s*\d+([.,]\d{1,2})?(\s*;\s*\d+([.,]\d{1,2})?)*\s*\z/

  # A plan of its own: a starting year and the monthly amounts.
  def custom_installments_plan?
    !custom_installments_starting_year.nil? && !custom_installments_cents.nil?
  end

  def custom_installments_string
    year = custom_installments_starting_year
    cents_list = custom_installments_cents
    if year.nil? || cents_list.nil?
      ""
    else
      cents_str = cents_list.map { |c| (c.to_f / 100).to_s.sub(/[.]0$/, "") }.join("; ")
      "#{year}: #{cents_str}"
    end
  end

  def custom_installments_string=(value)
    if value.blank? || value == "keine"
      self.custom_installments_starting_year = nil
      self.custom_installments_cents = nil
    else
      year_str, cents_list_str = value.split(":", 2)
      year = year_str.to_i
      cents_list = cents_list_str.split(";").map { |s| (BigDecimal(s.strip.tr(",", ".")) * 100).round.to_i }
      self.custom_installments_starting_year = year
      self.custom_installments_cents = cents_list
    end
  end

  ##
  # Return installments as YearMonthEur objects if this fee rule contains installment data.
  #
  # Returns nil if this fee ruls does not contain installment data.
  def yme_list
    Wsjrdp2027::PaymentPlanConversionHelper.year_and_cents_a_to_yme_list(custom_installments_starting_year, custom_installments_cents)
  end

  private

  def _normalize_custom_installments_payment_method
    self.custom_installments_payment_method =
      if custom_installments_plan?
        custom_installments_payment_method.presence || Wsjrdp2027::ParticipationFee::DEFAULT_PAYMENT_METHOD
      end
  end
end
