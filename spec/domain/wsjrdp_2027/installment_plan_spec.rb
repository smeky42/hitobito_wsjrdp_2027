# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The conversions as they were written before this class, to compare with.
module InstallmentPlanSpecOldConversion
  module_function

  def months(year, numbers)
    return nil if year.nil? || numbers.nil?

    year = year.to_i
    month = 1
    numbers.each_with_object([]) do |num, list|
      list << yield(year, month, num) if num != 0
      month += 1
      if month > 12
        year += 1
        month = 1
      end
    end
  end

  def eur_to_yme(year, eur_list)
    months(year, eur_list) { |y, m, eur| Wsjrdp2027::YearMonthEur.new([y, m], BigDecimal(eur.to_s)) }
  end

  def cents_to_yme(year, cents_list)
    months(year, cents_list) { |y, m, cents| Wsjrdp2027::YearMonthEur.new([y, m], BigDecimal(cents.to_i) / 100) }
  end

  def cents_to_raw(year, cents) = [BigDecimal(year), *cents.map { |c| BigDecimal(c.to_i) / 100 }]

  def raw_to_cents(raw) = raw[1..].map { |eur| (BigDecimal(eur.to_s) * 100).round.to_i }

  def ymc_to_raw(installments)
    first = installments.min_by(&:year_month)
    start = first.year_month.with(month: 1)
    eur_a = [0] * start.distance_in_months_to(installments.max_by(&:year_month))
    installments.each { |yme| eur_a[start.distance_in_months_to(yme)] = yme.eur }
    [BigDecimal(first.year), *eur_a]
  end
end

describe Wsjrdp2027::InstallmentPlan do
  let(:random) { Random.new(2027) }

  def random_cents(random)
    Array.new(random.rand(0..40)) do
      case random.rand(4)
      when 0 then 0
      when 1 then random.rand(1..99)
      else random.rand(1..3000) * 100 + [0, 50, 5, 99].sample(random: random)
      end
    end
  end

  def flat(list) = list&.map { |item| [item.year, item.month, item.eur, item.cents] }

  it "gives the same months as before, from cents and from raw euros" do
    500.times do
      year = random.rand(2024..2028)
      cents = random_cents(random)
      raw = InstallmentPlanSpecOldConversion.cents_to_raw(year, cents)

      expect(flat(described_class.from_cents(year, cents).yme_list)).to eq(flat(InstallmentPlanSpecOldConversion.cents_to_yme(year, cents)))
      expect(flat(described_class.from_raw_eur(raw).yme_list)).to eq(flat(InstallmentPlanSpecOldConversion.eur_to_yme(raw[0], raw[1..])))
    end
  end

  it "converts between cents and raw euros as before, both ways" do
    500.times do
      year = random.rand(2024..2028)
      cents = random_cents(random)
      raw = InstallmentPlanSpecOldConversion.cents_to_raw(year, cents)

      expect(described_class.from_cents(year, cents).to_raw_eur).to eq(raw)
      expect(described_class.from_raw_eur(raw).cents).to eq(InstallmentPlanSpecOldConversion.raw_to_cents(raw))
      expect(described_class.from_raw_eur(raw).starting_year).to eq(year)
    end
  end

  it "reads raw euros the way the database and the log hand them over" do
    raw = [BigDecimal("2025.000"), BigDecimal("0.000"), BigDecimal("312.500"), BigDecimal("0.010")]
    expect(described_class.from_raw_eur(raw)).to have_attributes(starting_year: 2025, cents: [0, 31_250, 1])
    expect(described_class.from_raw_eur(%w[2025.0 0.0 312.5])).to have_attributes(starting_year: 2025, cents: [0, 31_250])
    expect(described_class.from_raw_eur([2025])).to have_attributes(cents: [])
  end

  it "builds raw euros from YearMonthCents as before" do
    300.times do
      year = random.rand(2024..2028)
      cents = random_cents(random)
      installments = InstallmentPlanSpecOldConversion.months(year, cents) { |y, m, c| Wsjrdp2027::YearMonthCents.new([y, m], c) }
      next if installments.empty?

      expect(described_class.from_year_month_cents(installments.shuffle(random: random)).to_raw_eur)
        .to eq(InstallmentPlanSpecOldConversion.ymc_to_raw(installments))
    end
  end

  it "takes values as integers and writes the year as a decimal" do
    plan = described_class.from_cents("2026", ["500", 0, 250])

    expect(plan).to have_attributes(starting_year: 2026, cents: [500, 0, 250], sum_cents: 750)
    expect(plan.to_raw_eur.first).to be_a(BigDecimal)
  end

  describe "the types it answers" do
    def plans(random)
      year = random.rand(2024..2028)
      cents = random_cents(random)
      cents << 100 if cents.none?(&:positive?)
      installments = InstallmentPlanSpecOldConversion.months(year, cents) { |y, m, c| Wsjrdp2027::YearMonthCents.new([y, m], c) }
      [described_class.from_cents(year, cents),
        described_class.from_raw_eur(InstallmentPlanSpecOldConversion.cents_to_raw(year, cents)),
        described_class.from_year_month_cents(installments)]
    end

    def expect_types(plan, fraction: false)
      expect(plan).to be_a(described_class)
      expect(plan.starting_year).to be_an(Integer)
      expect(plan.currency).to eq "EUR"
      expect(plan.amounts).to all(be_a(BigDecimal))
      expect(plan.amounts).to be_frozen
      expect(plan.cents).to all(fraction ? (be_an(Integer).or be_a(BigDecimal)) : be_an(Integer))
      expect(plan.sum_cents).to fraction ? (be_an(Integer).or be_a(BigDecimal)) : be_an(Integer)
      expect(plan.to_raw_eur).to all(be_a(BigDecimal))
      expect(plan.yme_list).to all(be_a(Wsjrdp2027::YearMonthEur))
      plan.yme_list.each do |item|
        expect([item.year, item.month, item.cents]).to all(be_an(Integer))
        expect(item.eur).to be_a(BigDecimal)
      end
      expect(plan.text).to be_a(String)
    end

    it "answers integers for whole cents, BigDecimal euros and YearMonthEur months, from every from_*" do
      200.times { plans(random).each { |plan| expect_types(plan) } }
    end

    it "answers a BigDecimal for a fraction of a cent only" do
      plan = described_class.from_raw_eur([BigDecimal(2026), BigDecimal("1.005"), BigDecimal(2)])

      expect_types(plan, fraction: true)
      expect(plan.cents).to eq [BigDecimal("100.5"), 200]
      expect(plan.cents.map(&:class)).to eq [BigDecimal, Integer]
    end
  end

  describe "the currency" do
    it "is EUR unless given" do
      expect(described_class.from_cents(2026, [100]).currency).to eq "EUR"
      expect(described_class.from_raw_eur([2026, 1]).currency).to eq "EUR"
      expect(described_class.from_year_month_cents([Wsjrdp2027::YearMonthCents.new([2026, 1], 100)]).currency).to eq "EUR"
    end

    it "is kept where given, with the amounts and the text as in EUR" do
      plan = described_class.from_cents(2026, [100, 0, 250], currency: "USD")
      items = [Wsjrdp2027::YearMonthCents.new([2026, 1], 100)]

      expect(plan).to have_attributes(currency: "USD", cents: [100, 0, 250], text: "2026-01: 1; 0; 2,50")
      expect(described_class.from_year_month_cents(items, currency: "CHF").currency).to eq "CHF"
    end

    it "refuses euro-only answers for another currency" do
      plan = described_class.from_cents(2026, [100], currency: "USD")

      expect { plan.to_raw_eur }.to raise_error(ArgumentError)
      expect { plan.yme_list }.to raise_error(ArgumentError)
    end
  end

  it "is made only through the from_* methods" do
    plan = described_class.from_cents(2026, [100])

    expect { described_class.new(starting_year: 2026, amounts: [1], currency: "EUR") }.to raise_error(NoMethodError)
    expect { described_class[2026, [1], "EUR"] }.to raise_error(NoMethodError)
    expect { described_class.allocate }.to raise_error(NoMethodError)
    expect { plan.with(amounts: [1]) }.to raise_error(NoMethodError)
  end

  it "answers nil without a plan" do
    expect(described_class.from_cents(nil, [1])).to be_nil
    expect(described_class.from_cents(2026, nil)).to be_nil
    expect(described_class.from_raw_eur(nil)).to be_nil
    expect(described_class.from_raw_eur([])).to be_nil
    expect(described_class.from_year_month_cents([])).to be_nil
  end

  it "keeps an amount below a cent from the database exactly, in its months and in its text" do
    plan = described_class.from_raw_eur([BigDecimal(2026), BigDecimal("1.005"), BigDecimal(0), BigDecimal("150.5")])

    expect(plan.yme_list.map(&:eur)).to eq [BigDecimal("1.005"), BigDecimal("150.5")]
    expect(plan.to_raw_eur).to eq [2026, BigDecimal("1.005"), 0, BigDecimal("150.5")]
    expect(plan.text).to eq "2026-01: 1,005; 0; 150,50"
    expect { described_class.from_text(plan.text) }.to raise_error(described_class::Invalid)
  end

  it "refuses a missing amount or year" do
    expect { described_class.from_raw_eur([2026, nil]) }.to raise_error(ArgumentError)
    expect { described_class.from_raw_eur([nil, 5]) }.to raise_error(ArgumentError)
    expect { described_class.from_cents(2026, [100, nil]) }.to raise_error(ArgumentError)
  end
end
