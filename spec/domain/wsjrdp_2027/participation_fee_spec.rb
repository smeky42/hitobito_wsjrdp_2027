# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp2027::ParticipationFee do
  let(:person) { people(:yp_a_1) }

  def rule(status, cents: [0, 31_250, 50_000], **attrs)
    Wsj27RdpFeeRule.create!(people_id: person.id, status: status,
      custom_installments_starting_year: 2026, custom_installments_cents: cents,
      custom_installments_issue: "HELP-1", custom_installments_comment: "Vereinbarung", **attrs)
  end

  def person_yme_list(person)
    year, *eur = person.wsjrdp_raw_installments_eur
    Wsjrdp2027::PaymentPlanConversionHelper.year_and_eur_a_to_yme_list(year.to_i, eur)
  end

  describe "Person#participation_fee" do
    it "is one object per loaded person, dropped on reload" do
      fee = person.participation_fee

      expect(fee).to be_a(described_class).and have_attributes(person: person)
      expect(person.participation_fee).to equal(fee)
      expect(person.reload.participation_fee).not_to equal(fee)
    end
  end

  describe "#activate_installments!" do
    it "activates the planned rule and gives the person the same plan" do
      active = rule("active", cents: [10_000], activated_at: 1.day.ago)
      planned = rule("planned")

      expect(person.participation_fee.activate_installments!).to eq(planned)

      expect(active.reload.status).to eq("deleted")
      expect(planned.reload).to have_attributes(status: "active", prev_rule_id: active.id)
      person.reload
      expect(person).to have_attributes(wsjrdp_raw_installments_eur: [2026, 0, 312.5, 500],
        wsjrdp_installments_issue: "HELP-1", wsjrdp_installments_comment: "Vereinbarung")
      expect(person_yme_list(person)).to eq(planned.yme_list)
      expect(person.active_fee_rule).to eq(planned)
    end

    it "logs the plan and its issue on the person, not its comment" do
      rule("planned")

      expect {
        with_versioning { person.participation_fee.activate_installments! }
      }.to change { person.versions.count }.by(1)

      version = person.versions.reorder(:id).last
      expect(version.changeset.keys).to include("wsjrdp_raw_installments_eur", "wsjrdp_installments_issue")
      expect(version.changeset.keys).not_to include("wsjrdp_installments_comment")
      expect(version.object_changes).not_to include("Vereinbarung")
    end

    it "does nothing without a planned rule" do
      active = rule("active", activated_at: 1.day.ago)

      expect(person.participation_fee.activate_installments!).to be_nil
      expect(active.reload.status).to eq("active")
      expect(person.reload.wsjrdp_raw_installments_eur).to be_nil
    end

    it "leaves everything as it was when the person cannot be saved" do
      active = rule("active", activated_at: 1.day.ago)
      planned = rule("planned")
      allow(person).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)

      expect { person.participation_fee.activate_installments! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(active.reload.status).to eq("active")
      expect(planned.reload.status).to eq("planned")
    end
  end

  describe "total fee reduction" do
    let(:fee) { person.participation_fee }

    def plan_reduction
      person.update!(planned_total_fee_reduction: 250, planned_total_fee_reduction_issue: "HELP-2",
        planned_total_fee_reduction_hint: "Härtefall", planned_total_fee_reduction_comment: "Vereinbarung")
    end

    it "activates the plan and clears it" do
      plan_reduction

      expect(fee.activate_reduction!).to be(true)

      person.reload
      expect(person).to have_attributes(wsjrdp_total_fee_reduction: 250, wsjrdp_total_fee_reduction_issue: "HELP-2",
        wsjrdp_total_fee_reduction_hint: "Härtefall", wsjrdp_total_fee_reduction_comment: "Vereinbarung")
      expect(described_class::PLANNED_REDUCTION_ATTRS.map { |attr| person.public_send(attr) }).to all(be_nil)
    end

    it "activates nothing without a plan" do
      expect(fee.activate_reduction!).to be(false)
      expect(person.reload.wsjrdp_total_fee_reduction).to eq(0)
    end

    it "discards the plan and leaves the active reduction alone" do
      person.update!(wsjrdp_total_fee_reduction: 100)
      plan_reduction

      fee.discard_reduction!

      person.reload
      expect(person.wsjrdp_total_fee_reduction).to eq(100)
      expect(person.planned_total_fee_reduction).to be_nil
    end

    it "starts a plan from the active reduction without saving" do
      person.update!(wsjrdp_total_fee_reduction: 100, wsjrdp_total_fee_reduction_hint: "Härtefall")

      fee.plan_reduction_from_active

      expect(person).to have_attributes(planned_total_fee_reduction: 100, planned_total_fee_reduction_hint: "Härtefall")
      expect(person.reload.planned_total_fee_reduction).to be_nil
    end
  end

  describe ".raw_installments_eur" do
    it "is the plan as [starting year, euros per month from January]" do
      plan = described_class.raw_installments_eur(rule("planned", cents: [0, 31_250, 1]))
      expect(plan).to eq([2026, 0, BigDecimal("312.5"), BigDecimal("0.01")])
    end

    it "is nil without custom installments" do
      expect(described_class.raw_installments_eur(nil)).to be_nil
    end
  end
end
