# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe WsjrdpPaymentPlan do
  def plan(text) = described_class.new(wsjrdp_role: "TEST", single_payment: false, installments_string: text)

  it "stores the plan from January of its first year, in euros" do
    expect(plan("2025-12: 150; 350").raw_installments_eur).to eq [2025, *([0] * 11), 150, 350]
  end

  it "writes the plan back in its short form" do
    expect(plan("2025: 0; 0; 312,50; 0").installments_string).to eq "2025-03: 312,50"
  end

  it "refuses an unreadable plan, keeping what was typed and the stored plan" do
    record = plan("2026: 100")
    record.installments_string = "2026: 10; 2026-01: 5"

    expect(record).not_to be_valid
    expect(record.errors[:base]).to include("2026-01 kommt doppelt vor")
    expect(record.installments_string).to eq "2026: 10; 2026-01: 5"
    expect(record.raw_installments_eur).to eq [2026, 100]
  end

  it "shows a stored fraction of a cent unrounded, so that it cannot be saved again unnoticed" do
    record = described_class.new(wsjrdp_role: "TEST", single_payment: false, raw_installments_eur: [2026, BigDecimal("0.005")])

    expect(record.installments_string).to eq "2026-01: 0,005"
    shown = record.installments_string
    record.installments_string = shown
    expect(record).not_to be_valid
  end
end
