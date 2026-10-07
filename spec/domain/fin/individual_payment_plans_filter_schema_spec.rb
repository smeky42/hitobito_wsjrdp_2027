# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Individuelle Ratenpläne filter schema (Fin::IndividualPaymentPlansFilterSchema)
# compiled against `people`: the planned plan by a subquery into the fee
# rules, the payment method of the active plan, and the active plan's sum
# against the person's fee. The generic engine is covered standalone in
# spec/domain/wsjrdp/filtering_engine_spec.rb.
describe Fin::IndividualPaymentPlansFilterSchema do
  let(:schema) { described_class.bound }
  let(:yp) { people(:yp_a_1) }
  let(:other) { people(:yp_b_1) }
  let(:planner) { people(:ul_a_1) }

  # yp: 17 x 200 € by direct debit, the fee (3.400 €) exactly, confirmed.
  # other: 3.150 € by credit transfer -- 250 € short of the fee.
  # planner: a planned plan only.
  before do
    yp.update!(wsjrdp_raw_installments_eur: [2026, *([200] * 17)], wsjrdp_installments_issue: "HELP-830",
      status: "confirmed")
    other.update!(wsjrdp_raw_installments_eur: [2026, *([0] * 10), 2350, 0, 0, 400, 0, 0, 400],
      wsjrdp_installments_payment_method: "credit_transfer",
      wsjrdp_installments_comment: "Zahlt selbst per Überweisung")
    Wsj27RdpFeeRule.create!(people_id: planner.id, status: "planned", custom_installments_starting_year: 2026,
      custom_installments_cents: [20_000], custom_installments_issue: "HELP-1900",
      custom_installments_comment: "Neu geplant")
  end

  def apply(tree)
    Wsjrdp::Filtering::Compiler.new(schema)
      .apply(Wsjrdp::Filtering::Query.parse(tree))
  end

  def found(tree) = apply(tree).where(id: [yp.id, other.id, planner.id]).to_a

  it "tells a planned plan" do
    expect(found([[["planned", "in", "ja"]]])).to eq [planner]
    expect(found([[["planned", "in", "nein"]]])).to contain_exactly(yp, other)
  end

  it "tells the payment method of the active plan" do
    expect(found([[["payment_method", "in", "credit_transfer"]]])).to eq [other]
    expect(found([[["payment_method", "in", "direct_debit"]]])).to eq [yp]
  end

  it "tells a plan whose sum misses the fee, a planned plan alone counting as none" do
    expect(found([[["mismatch", "in", "ja"]]])).to eq [other]
    expect(found([[["mismatch", "in", "nein"]]])).to contain_exactly(yp, planner)
  end

  it "takes the reduction into the fee" do
    other.update!(wsjrdp_total_fee_reduction: 250)

    expect(found([[["mismatch", "in", "ja"]]])).to be_empty
  end

  it "tells a confirmed person" do
    expect(found([[["confirmed", "in", "ja"]]])).to eq [yp]
  end

  it "tells a person behind: by direct debit the months before the current one, by credit transfer the installments due" do
    travel_to(Time.zone.local(2026, 10, 8, 12)) do
      # yp, direct debit from January 2026: 1.800 € due by October, nothing came in.
      expect(found([[["behind", "in", "ja"]]])).to eq [yp]
      AccountingEntry.create!(subject: yp, author: people(:admin), amount_cents: 180_000, description: "Beitrag",
        value_date: Date.new(2026, 9, 7), booking_date: Date.new(2026, 9, 7))
      expect(found([[["behind", "in", "ja"]]])).to eq []

      # A collection of October exists: October's installment counts.
      WsjrdpDirectDebitPreNotification.create!(payment_initiation: WsjrdpPaymentInitiation.create!, subject: yp,
        author: people(:admin), amount_cents: 20_000, description: "Einzug", dbtr_name: "Muster",
        dbtr_iban: "DE02120300000000202051", collection_date: Date.new(2026, 10, 5), payment_status: "xml_generated")
      expect(found([[["behind", "in", "ja"]]])).to eq [yp]

      # other, credit transfer: from January 2026 on, 1.800 € due by October 8th.
      other.update!(wsjrdp_raw_installments_eur: [2026, *([200] * 17)])
      expect(found([[["behind", "in", "ja"]]])).to contain_exactly(yp, other)
      AccountingEntry.create!(subject: other, author: people(:admin), amount_cents: 180_000, description: "Beitrag",
        value_date: Date.new(2026, 9, 7), booking_date: Date.new(2026, 9, 7))
      expect(found([[["behind", "in", "nein"]]])).to contain_exactly(other, planner)
    end
  end

  it "searches names, issue and comment, the planned plan's too" do
    expect(found([[["search", "contains", "HELP-830"]]])).to eq [yp]
    expect(found([[["search", "contains", "per Überweisung"]]])).to eq [other]
    expect(found([[["search", "contains", "HELP-1900"]]])).to eq [planner]
    expect(found([[["search", "contains", "Neu geplant"]]])).to eq [planner]
    expect(found([[["search", "contains", planner.first_name]]])).to eq [planner]
  end
end
