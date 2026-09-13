# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The compensation of section 7.2 of the Teilnahme- und Reisebedingungen: the
# share of the fee that stays owed after a withdrawal. The fee below is an
# invented round figure, so every expectation reads as its percentage.
describe ContractHelper do
  # Round enough that a bracket's share is its percentage, in cents.
  let(:fee_cents) { 100_000 }

  def share_on(date)
    helper.compute_contractual_compensation_cents(fee_cents, today: Date.parse(date))
  end

  # Each bracket is named by its last day AND includes it -- "bis 31.05.2026"
  # means the 31st still pays half. The day after is what moves the share up,
  # which is why every boundary is asserted as a pair.
  it "keeps half the fee up to and including 31.05.2026" do
    expect(share_on("2026-01-01")).to eq(50_000)
    expect(share_on("2026-05-30")).to eq(50_000)
    expect(share_on("2026-05-31")).to eq(50_000)
  end

  it "asks three quarters from 01.06.2026 up to and including 31.12.2026" do
    expect(share_on("2026-06-01")).to eq(75_000)
    expect(share_on("2026-09-13")).to eq(75_000)
    expect(share_on("2026-12-31")).to eq(75_000)
  end

  it "asks nine tenths from 01.01.2027 up to and including 31.03.2027" do
    expect(share_on("2027-01-01")).to eq(90_000)
    expect(share_on("2027-03-30")).to eq(90_000)
    expect(share_on("2027-03-31")).to eq(90_000)
  end

  it "asks the whole fee from 01.04.2027" do
    expect(share_on("2027-04-01")).to eq(100_000)
    expect(share_on("2027-12-31")).to eq(100_000)
  end

  # Every bracket has to be reachable: a threshold written as YYYYDDMM lands
  # between two real dates and quietly swallows the bracket below it.
  it "reaches all four brackets across the jamboree's run-up" do
    shares = (Date.new(2026, 1, 1)..Date.new(2027, 6, 30)).step(1).map { |date|
      helper.compute_contractual_compensation_cents(fee_cents, today: date)
    }

    expect(shares.uniq.sort).to eq([50_000, 75_000, 90_000, 100_000])
  end

  it "falls back to today when no date is given" do
    travel_to(Date.new(2026, 6, 1)) do
      expect(helper.compute_contractual_compensation_cents(fee_cents)).to eq(75_000)
    end
  end

  # What the deregistration panel and the status page actually render
  # (Wsjrdp2027::Person#deregistration_contractual_compensation_cents and the
  # two amounts derived from it).
  describe "on a person" do
    let(:person) { people(:yp_a_1) }

    before { allow(person).to receive(:total_fee_cents).and_return(fee_cents) }

    it "shares the brackets" do
      travel_to(Date.new(2026, 6, 1)) do
        expect(person.deregistration_contractual_compensation_cents).to eq(75_000)
        expect(person.deregistration_contractual_compensation_cents(today: Date.new(2026, 5, 31)))
          .to eq(50_000)
      end
    end

    # The day the withdrawal was asked for is the day the bracket is read for.
    # Without it the share follows the calendar, which is what makes a request
    # that sits unanswered over a threshold cost more than it should.
    describe "the requested date" do
      it "fixes the bracket against a later day" do
        person.deregistration_requested_date = Date.new(2026, 5, 31)

        travel_to(Date.new(2027, 2, 1)) do
          expect(person.deregistration_compensation_date).to eq(Date.new(2026, 5, 31))
          expect(person.deregistration_contractual_compensation_cents).to eq(50_000)
        end
      end

      it "outranks the clock the caller hands in" do
        person.deregistration_requested_date = Date.new(2026, 5, 31)

        expect(person.deregistration_contractual_compensation_cents(today: Date.new(2027, 2, 1)))
          .to eq(50_000)
      end

      it "falls back to today while it is blank" do
        person.deregistration_requested_date = nil

        travel_to(Date.new(2027, 2, 1)) do
          expect(person.deregistration_compensation_date).to eq(Date.new(2027, 2, 1))
          expect(person.deregistration_contractual_compensation_cents).to eq(90_000)
        end
      end

      it "survives the round trip through the jsonb column as a date" do
        person.deregistration_requested_date = "2026-05-31"

        expect(person.deregistration_requested_date).to eq(Date.new(2026, 5, 31))
        expect(person.additional_info["deregistration_requested_date"]).to eq("2026-05-31")
      end

      # What the two pages put under the amount.
      it "says which day the amount was read for" do
        person.deregistration_requested_date = Date.new(2026, 5, 31)
        expect(helper.deregistration_compensation_date_hint(person))
          .to include("31.05.2026", "angefragt")

        person.deregistration_requested_date = nil
        travel_to(Date.new(2027, 2, 1)) do
          expect(helper.deregistration_compensation_date_hint(person))
            .to include("01.02.2027", "heute")
        end
      end
    end

    # Whatever is entered by hand wins over the bracket, for both amounts.
    it "gives way to an entered compensation" do
      allow(person).to receive_messages(amount_paid_cents: 60_000,
        deregistration_actual_compensation_cents: 20_000)

      travel_to(Date.new(2026, 6, 1)) do
        expect(person.deregistration_refund_cents).to eq(40_000)
        expect(person.deregistration_open_cents).to eq(0)
      end
    end

    it "otherwise settles against the bracket" do
      allow(person).to receive_messages(amount_paid_cents: 60_000,
        deregistration_actual_compensation_cents: nil)

      travel_to(Date.new(2026, 6, 1)) do
        expect(person.deregistration_refund_cents).to eq(0)
        expect(person.deregistration_open_cents).to eq(15_000)
      end
    end
  end
end
