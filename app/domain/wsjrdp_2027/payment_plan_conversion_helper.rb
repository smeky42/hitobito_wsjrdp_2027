# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::PaymentPlanConversionHelper
  module_function

  BIG_DECIMAL_100 = BigDecimal(100)

  def installments_to_raw_installments_eur(installments)
    return nil if installments.blank?
    first_installment = installments.min_by { |i| i.year_month }
    start = first_installment.year_month.with(month: 1)
    last_installments = installments.max_by { |i| i.year_month }
    num_months = start.distance_in_months_to(last_installments)
    eur_a = [0] * num_months
    installments.each do |yme|
      eur_a[start.distance_in_months_to(yme)] = yme.eur
    end
    [BigDecimal(first_installment.year), *eur_a]
  end

  def year_and_eur_a_to_yme_list(year, eur_list)
    year_and_numbers_to_installments(year, eur_list) do |year, month, eur|
      Wsjrdp2027::YearMonthEur.new([year, month], BigDecimal(eur.to_s))
    end
  end

  def year_and_eur_a_to_installments_ymc(year, eur_list)
    year_and_numbers_to_installments(year, eur_list) do |year, month, eur|
      Wsjrdp2027::YearMonthCents.new([year, month], BigDecimal(eur.to_s) * BIG_DECIMAL_100)
    end
  end

  def year_and_cents_a_to_yme_list(year, cents_list)
    year_and_numbers_to_installments(year, cents_list) do |year, month, cents|
      Wsjrdp2027::YearMonthEur.new([year, month], BigDecimal(cents.to_i) / BIG_DECIMAL_100)
    end
  end

  def year_and_cents_a_to_installments_ymc(year, cents_list)
    year_and_numbers_to_installments(year, cents_list) do |year, month, cents|
      Wsjrdp2027::YearMonthCents.new([year, month], cents.to_i)
    end
  end

  def installments_to_installments_string(installments, blank_year: 2025)
    raw_installments_eur_to_installments_string(
      installments_to_raw_installments_eur(installments)
    )
  end

  def raw_installments_eur_to_installments_string(installments)
    return nil if installments.blank? || installments.empty?
    year = installments[0].to_i
    nums = installments[1..]
    nums_str = nums.map { |d| d.to_s.sub(/[.]0$/, "") }.join("; ")
    "#{year}: #{nums_str}"
  end

  def installments_string_to_raw_installments_eur(value)
    if value.blank? || value == "keine"
      nil
    else
      year_str, nums_str = value.split(":", 2)
      year = year_str.to_i
      nums = nums_str.split(";").map { |s| BigDecimal(s) }
      [year, *nums]
    end
  end

  def year_and_numbers_to_installments(year, numbers)
    return nil if year.nil? || numbers.nil?
    year = year.to_i
    month = 1
    installments = []
    numbers.each do |num|
      if num != 0
        installments << yield(year, month, num)
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
