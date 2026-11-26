# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Standalone, no Rails:
#   bundle exec rspec ../hitobito_wsjrdp_2027/spec/domain/wsjrdp_2027/installment_plan_text_spec.rb
module Wsjrdp2027; end
require_relative "../../../app/domain/wsjrdp_2027/installment_plan"

# The plan as text: from_text and text.
describe Wsjrdp2027::InstallmentPlan do
  def text_of(year, cents) = described_class.from_cents(year, cents).text

  def parse(text) = described_class.from_text(text).then { |plan| {starting_year: plan.starting_year, cents: plan.cents} }

  def plan(year, *euros) = {starting_year: year, cents: euros.map { |eur| (eur * 100).round }}

  def months(year, first_month, *euros) = plan(year, *([0] * (first_month - 1)), *euros)

  # The format "YYYY: amount; amount; ..." the form took before, read as it
  # was read then, without zero months at the end.
  def old_parse(text)
    year, list = text.split(":", 2)
    cents = list.split(";").map { |s| (BigDecimal(s.strip.tr(",", ".")) * 100).round.to_i }
    cents.pop while cents.last&.zero?
    {starting_year: year.to_i, cents: cents}
  end

  describe "examples" do
    it "answers an InstallmentPlan in integer cents" do
      plan = described_class.from_text("2026-12: 312,50; 0,5")

      expect(plan).to be_a(Wsjrdp2027::InstallmentPlan)
      expect([plan.starting_year, *plan.cents]).to all(be_an(Integer))
    end

    it "takes a currency, EUR unless given" do
      expect(described_class.from_text("2026: 1").currency).to eq "EUR"
      expect(described_class.from_text("2026: 1", currency: "USD").currency).to eq "USD"
    end

    it "reads the old format as before" do
      expect(parse("2025: 0; 0; 0; 0; 0; 1400")).to eq months(2025, 6, 1400)
      expect(parse("2026: 312,50; 500")).to eq plan(2026, 312.5, 500)
      expect(parse(" 2026 : 0 ; 0 ; 500 ")).to eq months(2026, 3, 500)
    end

    it "starts at a month" do
      expect(parse("2025-06: 1400")).to eq months(2025, 6, 1400)
      expect(parse("2025-6: 1400")).to eq months(2025, 6, 1400)
    end

    it "continues into the next year" do
      expect(parse("2026-12: 500; 100; 100")).to eq months(2026, 12, 500, 100, 100)
    end

    it "jumps forward to a date, leaving the months between at zero" do
      expect(parse("2026: 10; 2026-06: 5")).to eq months(2026, 1, 10, 0, 0, 0, 0, 5)
      expect(parse("2026-03: 100; 2027: 50; 50")).to eq months(2026, 3, 100, *[0] * 9, 50, 50)
    end

    it "takes no-break spaces and other whitespace like spaces" do
      expect(parse("2026:\u00A05;\u202F6;\t7")).to eq plan(2026, 5, 6, 7)
      expect(parse("2026: 21474836,47")).to eq plan(2026, 21_474_836.47)
    end

    it "reads a value that is not a string as its text" do
      expect { described_class.from_text(5) }.to raise_error(described_class::Invalid)
    end

    it "skips empty elements" do
      expect(parse("2026: 10;; 20;")).to eq plan(2026, 10, 20)
      expect(parse(";2026: 10")).to eq plan(2026, 10)
    end

    it "drops zero months at the end" do
      expect(parse("2026: 100; 0; 0")).to eq plan(2026, 100)
      expect(parse("2026: 0")).to eq plan(2026)
    end

    it "takes a point or a comma before the cents, and zeros after them" do
      expect(parse("2026: 1.6; 1,05")).to eq plan(2026, 1.6, 1.05)
      expect(parse("2026-01: 0,50000000; 7.000")).to eq plan(2026, 0.5, 7)
    end
  end

  describe "refusals" do
    {
      "" => "ausgefüllt",
      "   " => "ausgefüllt",
      " ; ; " => "ausgefüllt",
      "2026-123: 5" => "kein Datum",
      "20261: 5" => "kein Datum",
      "2026: 5\n6" => "kein Betrag",
      "2026-06: 5; 2026-05: 3" => "liegt vor",
      "2026: 21474836,48" => "zu groß",
      "9999-12: 1; 2" => "9999-12",
      "0999: 5" => "zwischen 1000 und 9999",
      "500; 100" => "mit einem Datum beginnen",
      "2026: 10; 2026-01: 5" => "doppelt",
      "2026-06: 5; 2026-01: 3" => "liegt vor",
      "2026-06:" => "keinen Betrag",
      "2026-13: 5" => "zwischen 1 und 12",
      "2026-0: 5" => "zwischen 1 und 12",
      "26: 5" => "kein Datum",
      "2026: abc" => "kein Betrag",
      "2026: -5" => "kein Betrag",
      "2026: 1,234" => "Bruchteile eines Cents",
      "2026: 1,005" => "Bruchteile eines Cents",
      "2026: 1,00000001" => "Bruchteile eines Cents"
    }.each do |text, message|
      it "refuses #{text.inspect}" do
        expect { described_class.from_text(text) }.to raise_error(described_class::Invalid, /#{message}/)
      end
    end
  end

  describe "properties" do
    let(:random) { Random.new(2027) }

    def amount_text(random)
      euros = random.rand(0..2000)
      case random.rand(4)
      when 0 then "#{euros},#{random.rand(0..99).to_s.rjust(2, "0")}"
      when 1 then "#{euros}.#{random.rand(0..9)}"
      else euros.to_s
      end
    end

    def old_format_text(random)
      amounts = Array.new(random.rand(1..30)) { amount_text(random) }
      "#{random.rand(2024..2028)}: #{amounts.join("; ")}"
    end

    it "reads every text of the old format as the old parser did" do
      200.times do
        text = old_format_text(random)
        expect(parse(text)).to eq(old_parse(text)), text
      end
    end

    # The same installments; a starting year with no installment in it may
    # move forward.
    def installments(plan) = plan[:cents].each_with_index.reject { |cents, _| cents.zero? }
      .map { |cents, offset| [plan[:starting_year] * 12 + offset, cents] }

    it "parses its own short format back to the same installments" do
      200.times do
        parsed = described_class.from_text(old_format_text(random))
        short = parsed.text
        expect(installments(parse(short))).to eq(installments(starting_year: parsed.starting_year, cents: parsed.cents)), short
      end
    end

    it "ignores empty elements wherever they are" do
      200.times do
        text = old_format_text(random)
        padded = text.split(";").flat_map { |element| [element, *([" "] * random.rand(0..2))] }.join(";")
        expect(parse(padded)).to eq(parse(text)), padded
      end
    end

    it "keeps the sum of the amounts" do
      200.times do
        text = old_format_text(random)
        expected = text.split(":", 2).last.split(";").sum { |s| (BigDecimal(s.strip.tr(",", ".")) * 100).round }
        expect(parse(text)[:cents].sum).to eq(expected), text
      end
    end
  end

  describe "#text" do
    it "writes the short form" do
      expect(text_of(2026, months(2026, 12, 500)[:cents] + [10_000, 10_000]))
        .to eq "2026-12: 500; 100; 100"
      expect(text_of(2026, [1000, 0, 0, 0, 0, 500])).to eq "2026-01: 10; 2026-06: 5"
      expect(text_of(2026, [10_000, 0, 10_000])).to eq "2026-01: 100; 0; 100"
      expect(text_of(2026, [10_000, 0, 0, 10_000])).to eq "2026-01: 100; 2026-04: 100"
      expect(text_of(2026, [31_250, 50_000, 0])).to eq "2026-01: 312,50; 500"
      expect(text_of(2026, [])).to eq "2026: 0"
      expect(text_of(2026, [0, 0])).to eq "2026: 0"
      expect(text_of(2026, [-150, -5])).to eq "2026-01: -1,50; -0,05"
    end
  end
end
