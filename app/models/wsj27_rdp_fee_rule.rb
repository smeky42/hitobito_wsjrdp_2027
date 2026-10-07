# frozen_string_literal: true

class Wsj27RdpFeeRule < ActiveRecord::Base
  include ContractHelper
  include WsjrdpInstallmentsHelper

  # rubocop:disable Rails/InverseOf
  belongs_to :person, foreign_key: :people_id, optional: true, class_name: "Person"
  belongs_to :custom_installments_payment_plan, optional: true, class_name: "WsjrdpPaymentPlan"
  # rubocop:enable Rails/InverseOf

  # The rules that carry a plan of their own (a starting year and the monthly
  # amounts), as opposed to a reduction alone.
  scope :with_plan, -> { where.not(custom_installments_starting_year: nil).where.not(custom_installments_cents: nil) }

  # The payment method goes with the plan: present exactly when a plan is,
  # direct debit unless chosen otherwise (the database checks the same).
  before_validation :_normalize_custom_installments_payment_method
  # additional_info is never NULL (database default {}); nil stands for {}.
  before_validation { self.additional_info ||= {} }

  def soft_delete!
    self.deleted_at = Time.zone.now
    self.status = "deleted"
    save!
  end

  def activate!(prev_rule_id = nil)
    self.activated_at = Time.zone.now
    self.status = "active"
    if prev_rule_id
      self.prev_rule_id = prev_rule_id
    end
    save!
  end

  def custom_installments?
    ![custom_installments_starting_year.nil?, custom_installments_cents.nil?,
      custom_installments_comment.blank?, custom_installments_issue.blank?].all?
  end

  # A plan of its own: a starting year and the monthly amounts.
  def custom_installments_plan?
    !custom_installments_starting_year.nil? && !custom_installments_cents.nil?
  end

  def custom_installments_payment_method_display
    Wsjrdp2027::ParticipationFee.payment_method_label(custom_installments_payment_method)
  end

  def custom_installments_display
    custom_installments_string
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
      cents_list = cents_list_str.split(";").map { |s| (s.strip.to_f * 100).round }
      self.custom_installments_starting_year = year
      self.custom_installments_cents = cents_list
    end
  end

  def custom_installments_string_changed?
    custom_installments_starting_year_changed? || custom_installments_cents_changed?
  end

  def custom_installments_issue_display
    issue = custom_installments_issue
    if issue.nil? || !(issue =~ /^(HELP|FIN)-[0-9]+$/)
      issue
    else
      "<a href=\"https://helpdesk.worldscoutjamboree.de/browse/#{issue}\">#{issue}</a>".html_safe
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
