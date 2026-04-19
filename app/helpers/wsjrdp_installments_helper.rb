# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module WsjrdpInstallmentsHelper
  extend ActiveSupport::Concern

  BIG_DECIMAL_100 = BigDecimal(100).freeze

  YP_REGULAR_PAYER_INSTALLMENTS = [
    Wsjrdp2027::YearMonthCents.new([2025, 12], 30000),
    Wsjrdp2027::YearMonthCents.new([2026, 1], 50000),
    Wsjrdp2027::YearMonthCents.new([2026, 2], 50000),
    Wsjrdp2027::YearMonthCents.new([2026, 3], 50000),
    Wsjrdp2027::YearMonthCents.new([2026, 8], 40000),
    Wsjrdp2027::YearMonthCents.new([2026, 11], 40000),
    Wsjrdp2027::YearMonthCents.new([2027, 2], 40000),
    Wsjrdp2027::YearMonthCents.new([2027, 5], 40000)
  ].freeze
  UL_REGULAR_PAYER_INSTALLMENTS = [
    Wsjrdp2027::YearMonthCents.new([2025, 12], 15000),
    Wsjrdp2027::YearMonthCents.new([2026, 1], 35000),
    Wsjrdp2027::YearMonthCents.new([2026, 2], 35000),
    Wsjrdp2027::YearMonthCents.new([2026, 3], 35000),
    Wsjrdp2027::YearMonthCents.new([2026, 8], 30000),
    Wsjrdp2027::YearMonthCents.new([2026, 11], 30000),
    Wsjrdp2027::YearMonthCents.new([2027, 2], 30000),
    Wsjrdp2027::YearMonthCents.new([2027, 5], 30000)
  ].freeze
  IST_REGULAR_PAYER_INSTALLMENTS = [
    Wsjrdp2027::YearMonthCents.new([2025, 12], 20000),
    Wsjrdp2027::YearMonthCents.new([2026, 1], 40000),
    Wsjrdp2027::YearMonthCents.new([2026, 2], 40000),
    Wsjrdp2027::YearMonthCents.new([2026, 3], 40000),
    Wsjrdp2027::YearMonthCents.new([2026, 8], 30000),
    Wsjrdp2027::YearMonthCents.new([2026, 11], 30000),
    Wsjrdp2027::YearMonthCents.new([2027, 2], 30000),
    Wsjrdp2027::YearMonthCents.new([2027, 5], 30000)
  ].freeze
  BMT_REGULAR_PAYER_INSTALLMENTS = [
    Wsjrdp2027::YearMonthCents.new([2025, 12], 20000),
    Wsjrdp2027::YearMonthCents.new([2026, 1], 40000),
    Wsjrdp2027::YearMonthCents.new([2026, 2], 40000),
    Wsjrdp2027::YearMonthCents.new([2026, 3], 40000),
    Wsjrdp2027::YearMonthCents.new([2026, 8], 30000),
    Wsjrdp2027::YearMonthCents.new([2026, 11], 30000),
    Wsjrdp2027::YearMonthCents.new([2027, 2], 30000),
    Wsjrdp2027::YearMonthCents.new([2027, 5], 30000)
  ].freeze
  CMT_REGULAR_PAYER_INSTALLMENTS = [
    Wsjrdp2027::YearMonthCents.new([2025, 12], 5000),
    Wsjrdp2027::YearMonthCents.new([2026, 1], 25000),
    Wsjrdp2027::YearMonthCents.new([2026, 2], 25000),
    Wsjrdp2027::YearMonthCents.new([2026, 3], 25000),
    Wsjrdp2027::YearMonthCents.new([2026, 8], 20000),
    Wsjrdp2027::YearMonthCents.new([2026, 11], 20000),
    Wsjrdp2027::YearMonthCents.new([2027, 2], 20000),
    Wsjrdp2027::YearMonthCents.new([2027, 5], 20000)
  ].freeze
  EXT_REGULAR_PAYER_INSTALLMENTS = [].freeze

  YP_EARLY_PAYER_INSTALLMENTS = [Wsjrdp2027::YearMonthCents.new([2025, 8], 340000)].freeze
  UL_EARLY_PAYER_INSTALLMENTS = [Wsjrdp2027::YearMonthCents.new([2025, 8], 240000)].freeze
  IST_EARLY_PAYER_INSTALLMENTS = [Wsjrdp2027::YearMonthCents.new([2025, 8], 260000)].freeze
  BMT_EARLY_PAYER_INSTALLMENTS = [Wsjrdp2027::YearMonthCents.new([2025, 8], 260000)].freeze
  CMT_EARLY_PAYER_INSTALLMENTS = [Wsjrdp2027::YearMonthCents.new([2025, 8], 160000)].freeze
  EXT_EARLY_PAYER_INSTALLMENTS = [].freeze

  PAYMENT_ROLE_TO_FULL_REGULAR_FEE_CENTS = {
    "CMT" => CMT_EARLY_PAYER_INSTALLMENTS[0]&.cents || 0,
    "EXT" => EXT_EARLY_PAYER_INSTALLMENTS[0]&.cents || 0,
    "IST" => IST_EARLY_PAYER_INSTALLMENTS[0]&.cents || 0,
    "BMT" => IST_EARLY_PAYER_INSTALLMENTS[0]&.cents || 0,
    "UL" => UL_EARLY_PAYER_INSTALLMENTS[0]&.cents || 0,
    "YP" => YP_EARLY_PAYER_INSTALLMENTS[0]&.cents || 0,
    "EarlyPayer::Group::Extern::Member" => EXT_EARLY_PAYER_INSTALLMENTS[0]&.cents || 0,
    "EarlyPayer::Group::Ist::Member" => IST_EARLY_PAYER_INSTALLMENTS[0]&.cents || 0,
    "EarlyPayer::Group::Root::Member" => CMT_EARLY_PAYER_INSTALLMENTS[0]&.cents || 0,
    "EarlyPayer::Group::Unit::Leader" => UL_EARLY_PAYER_INSTALLMENTS[0]&.cents || 0,
    "EarlyPayer::Group::Unit::Member" => YP_EARLY_PAYER_INSTALLMENTS[0]&.cents || 0,
    "RegularPayer::Group::Extern::Member" => EXT_EARLY_PAYER_INSTALLMENTS[0]&.cents || 0,
    "RegularPayer::Group::Ist::Member" => IST_EARLY_PAYER_INSTALLMENTS[0]&.cents || 0,
    "RegularPayer::Group::Root::Member" => CMT_EARLY_PAYER_INSTALLMENTS[0]&.cents || 0,
    "RegularPayer::Group::Unit::Leader" => UL_EARLY_PAYER_INSTALLMENTS[0]&.cents || 0,
    "RegularPayer::Group::Unit::Member" => YP_EARLY_PAYER_INSTALLMENTS[0]&.cents || 0
  }.freeze

  PAYMENT_ROLE_TO_FULL_REGULAR_FEE_EUR = PAYMENT_ROLE_TO_FULL_REGULAR_FEE_CENTS.transform_values { |cents| BigDecimal(cents) / BIG_DECIMAL_100 }.freeze

  included do
    def regular_full_fee_cents_for_role(role)
      PAYMENT_ROLE_TO_FULL_REGULAR_FEE_CENTS[role]
    end

    def regular_full_fee_eur_for_role(role)
      PAYMENT_ROLE_TO_FULL_REGULAR_FEE_EUR[role]
    end

    def default_payment_plans(single_payment:)
      single_payment ? single_payment_plans : regular_payment_plans
    end

    def default_regular_payment_installments_table  # rubocop:disable Metrics/MethodLength
      plans = default_payment_plans(single_payment: false)
      year_month_set = Set.new
      plans.each do |plan|
        plan.yme_list.each do |yme|
          year_month_set << yme.year_month
        end
      end
      year_month_list = year_month_set.to_a.sort
      plans.map do |plan|
        yme_list = plan.yme_list
        yme_list_for_table = year_month_list.map { |ym| (yme_list.find { |elt| elt.year_month == ym }) || Wsjrdp2027::YearMonthEur.new(ym, 0) }
        [plan.wsjrdp_role, *yme_list_for_table]
      end
    end

    def default_single_payment_total_fee_eur_table
      plans = default_payment_plans(single_payment: true)
      plans.map { |plan| [plan.wsjrdp_role, plan.total_eur] }
    end
  end

  private

  def regular_payment_plans
    @regular_payment_plans ||= [
      WsjrdpPaymentPlan.from_parts(wsjrdp_role: "YP", single_payment: false, installments: YP_REGULAR_PAYER_INSTALLMENTS, readonly: true),
      WsjrdpPaymentPlan.from_parts(wsjrdp_role: "UL", single_payment: false, installments: UL_REGULAR_PAYER_INSTALLMENTS, readonly: true),
      WsjrdpPaymentPlan.from_parts(wsjrdp_role: "IST", single_payment: false, installments: IST_REGULAR_PAYER_INSTALLMENTS, readonly: true),
      WsjrdpPaymentPlan.from_parts(wsjrdp_role: "CMT", single_payment: false, installments: CMT_REGULAR_PAYER_INSTALLMENTS, readonly: true)
    ]
  end

  def single_payment_plans
    @single_payment_plans ||= [
      WsjrdpPaymentPlan.from_parts(wsjrdp_role: "YP", single_payment: true, installments: YP_EARLY_PAYER_INSTALLMENTS, readonly: true),
      WsjrdpPaymentPlan.from_parts(wsjrdp_role: "UL", single_payment: true, installments: UL_EARLY_PAYER_INSTALLMENTS, readonly: true),
      WsjrdpPaymentPlan.from_parts(wsjrdp_role: "IST", single_payment: true, installments: IST_EARLY_PAYER_INSTALLMENTS, readonly: true),
      WsjrdpPaymentPlan.from_parts(wsjrdp_role: "CMT", single_payment: true, installments: CMT_EARLY_PAYER_INSTALLMENTS, readonly: true)
    ]
  end
end
