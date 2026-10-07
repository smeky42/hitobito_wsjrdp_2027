# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The rows of the Individuelle Ratenpläne list: a person's active plan from
# their own columns, the planned one from the planned fee rule, the standard
# plan of the role while only a plan exists.
describe Fin::IndividualPaymentPlanRow do
  let(:yp) { people(:yp_a_1) }
  let(:planner) { people(:ul_a_1) }

  def rule(person, status, cents:, **attrs)
    Wsj27RdpFeeRule.create!(people_id: person.id, status: status, custom_installments_starting_year: 2026,
      custom_installments_cents: cents, **attrs)
  end

  def month(year, month) = Wsjrdp2027::YearMonth.new(year, month)

  describe Fin::ListedPaymentPlan do
    it "reads the active plan from the person's columns" do
      yp.update!(wsjrdp_raw_installments_eur: [2026, 0, BigDecimal("312.5"), 500], wsjrdp_installments_issue: "HELP-1",
        wsjrdp_installments_comment: "Vereinbarung", wsjrdp_installments_payment_method: "credit_transfer")

      plan = Fin::ListedPaymentPlan.active_of(yp)

      expect(plan).to have_attributes(kind: :active, payment_method: "credit_transfer", issue: "HELP-1",
        comment: "Vereinbarung", count: 2, total_cents: 81_250, first_month: month(2026, 2), last_month: month(2026, 3))
      expect(plan.cents_in(month(2026, 1))).to eq 0
      expect(plan.cents_in(month(2026, 2))).to eq 31_250
      expect(plan.gap_cents(100_000)).to eq(-18_750)
      expect(plan).to be_active
    end

    it "is nil without a plan" do
      expect(Fin::ListedPaymentPlan.active_of(yp)).to be_nil
      reduction = Wsj27RdpFeeRule.create!(people_id: yp.id, status: "planned", total_fee_reduction_cents: 1000)
      expect(Fin::ListedPaymentPlan.planned_of(reduction)).to be_nil
      expect(Fin::ListedPaymentPlan.planned_of(nil)).to be_nil
      expect(Fin::ListedPaymentPlan.standard_of(nil)).to be_nil
    end
  end

  describe "the strip's months (Fin::ListedPaymentPlan#strip_range)" do
    def plan_with(months)
      Fin::ListedPaymentPlan.new(kind: :active, payment_method: "direct_debit", issue: nil, comment: nil,
        yme_list: months.map { |year, mon| Wsjrdp2027::YearMonthEur.new(year_month: [year, mon], eur: 100) })
    end

    def range(months) = plan_with(months).strip_range.map { |ym| [ym.year, ym.month] }

    it "is December 2025 to May 2027 for a plan within that span, and without installments" do
      expect(range([[2026, 1], [2027, 5]])).to eq [[2025, 12], [2027, 5]]
      expect(range([[2026, 6], [2027, 3]])).to eq [[2025, 12], [2027, 5]]
      expect(range([])).to eq [[2025, 12], [2027, 5]]
      expect(plan_with([[2026, 1]]).strip_length).to eq 18
    end

    it "stretches to a plan's last month beyond the span, and to its first where that comes earlier" do
      expect(range([[2026, 1], [2027, 8]])).to eq [[2025, 12], [2027, 8]]
      expect(range([[2025, 8], [2027, 8]])).to eq [[2025, 8], [2027, 8]]
    end

    it "shows a plan that starts and ends earlier from its start, for at least the span's length" do
      expect(range([[2025, 8]])).to eq [[2025, 8], [2027, 1]]
      expect(range([[2025, 8], [2026, 1]])).to eq [[2025, 8], [2027, 1]]
      expect(plan_with([[2025, 8]]).strip_months.size).to eq 18
    end
  end

  describe ".people_with_plan" do
    it "is the people with an active or a planned rule that carries a plan, a reduction alone aside" do
      rule(yp, "active", cents: [1])
      rule(planner, "planned", cents: [1])
      Wsj27RdpFeeRule.create!(people_id: people(:yp_b_1).id, status: "active", total_fee_reduction_cents: 1000)

      expect(described_class.people_with_plan.pluck(:id)).to contain_exactly(yp.id, planner.id)
    end
  end

  describe ".for" do
    # The migrated standard plans aside: the examples set up their own.
    before { WsjrdpPaymentPlan.kept.destroy_all }

    it "pairs the person with the active plan, the planned one and the activation" do
      active = rule(yp, "active", cents: [20_000] * 3, activated_at: Time.zone.local(2026, 1, 5, 10))
      yp.update!(Wsjrdp2027::ParticipationFee.person_installments_attrs(active))
      rule(yp, "planned", cents: [30_000] * 2, custom_installments_issue: "HELP-9")

      row = described_class.for([yp]).first

      expect(row.person).to eq yp
      expect(row.active_plan).to have_attributes(kind: :active, total_cents: 60_000, count: 3,
        payment_method: "direct_debit")
      expect(row.planned_plan).to have_attributes(kind: :planned, total_cents: 60_000, issue: "HELP-9")
      expect(row.activated_at).to eq Time.zone.local(2026, 1, 5, 10)
      expect(row.shown_plan).to eq row.active_plan
      expect(row).to be_planned
      expect(row.plans.map(&:plan)).to eq [row.planned_plan]
      expect(row.plans.first.fee_cents).to eq yp.total_fee_cents
      expect(row.fee_cents).to eq yp.total_fee_cents
      expect(row.open_cents).to eq yp.total_fee_cents - yp.amount_paid_cents
      expect(row.progress).to be_a(Fin::PaymentProgress)
      expect(row.progress.plan).to eq row.active_plan
    end

    it "dates an activation without activated_at by the rule's creation" do
      active = rule(yp, "active", cents: [20_000])
      yp.update!(Wsjrdp2027::ParticipationFee.person_installments_attrs(active))

      expect(described_class.for([yp]).first.activated_at).to eq active.created_at
    end

    it "shows the standard plan of the role while only a planned plan exists" do
      WsjrdpPaymentPlan.create!(wsjrdp_role: "UL", single_payment: false, payment_method: "direct_debit",
        raw_installments_eur: [2025, *([0] * 11), 150, 350])
      rule(planner, "planned", cents: [10_000])

      row = described_class.for([planner]).first

      expect(row.active_plan).to be_nil
      expect(row.activated_at).to be_nil
      expect(row.shown_plan).to have_attributes(kind: :standard, total_cents: 50_000, count: 2,
        first_month: month(2025, 12), last_month: month(2026, 1), payment_method: "direct_debit")
      expect(row.shown_plan).to be_standard
      expect(row.plans.size).to eq 1
    end

    it "shows nothing in the row of a role without a standard plan" do
      rule(planner, "planned", cents: [10_000])

      row = described_class.for([planner]).first

      expect(row.shown_plan).to be_nil
      expect(row.plans.first.plan).to be_planned
    end
  end
end
