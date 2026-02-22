# frozen_string_literal: true

class Wsj27RdpFeeRule < ActiveRecord::Base
  include ContractHelper

  # rubocop:disable Rails/InverseOf
  belongs_to :person, foreign_key: :people_id, optional: true, class_name: "Person"
  # rubocop:enable Rails/InverseOf

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

  def total_fee_reduction?
    !(total_fee_reduction_cents.nil? || total_fee_reduction_cents == 0)
  end

  def total_fee_reduction_display
    if total_fee_reduction_cents.nil? || total_fee_reduction_cents == 0
      "keine"
    else
      format_cents_de(total_fee_reduction_cents)
    end
  end

  def custom_installments?
    ![custom_installments_starting_year.nil?, custom_installments_cents.nil?,
      custom_installments_comment.blank?, custom_installments_issue.blank?].all?
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
  # Return installments (in cents) if this fee rule contains installment data.
  #
  # Returns nil if this fee ruls does not contain installment data.
  #
  # The returned list has entries of the form [[year, month], cents].
  def get_installments_cents
    year = custom_installments_starting_year
    list_of_cent_values = custom_installments_cents
    if year.nil? || list_of_cent_values.nil?
      nil
    else
      month = 1
      installments = []
      list_of_cent_values.each do |cents|
        if cents != 0
          installments << Wsjrdp2027::YearMonthCents.new([year, month], cents)
        end
        month += 1
        if month > 12
          year += 1
          month = 1
        end
      end
      installments
    end
  end

  def get_installments_cents_if_active
    if status == "active"
      get_installments_cents
    end
  end
end
