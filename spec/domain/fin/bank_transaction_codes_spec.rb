# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Fin::BankTransactionCodes do
  it "splits the ISO code into its labelled parts" do
    parts = described_class.iso_parts("PMNT+IDDT+UPDD")

    expect(parts.map(&:code)).to eq(%w[PMNT IDDT UPDD])
    expect(parts.last).to have_attributes(label: "Rücklastschrift", name: "Reversal Due To Return/Unpaid Direct Debit")
  end

  it "keeps a part it does not know as its code" do
    expect(described_class.iso_parts("PMNT+ZZZZ+YYYY").last).to have_attributes(code: "YYYY", known?: false)
  end

  it "leaves out the Primanota of the German code and keeps a Textschlüsselergänzung" do
    parts = described_class.dk_parts("NRTI+109+9002/405+901")

    expect(parts[:swift]).to have_attributes(code: "NRTI", label: "Rückgabe")
    expect(parts[:gvc]).to have_attributes(code: "109", known?: true)
    expect(parts[:text_key].code).to eq("901")
  end

  it "reads a German code without Primanota and Textschlüsselergänzung" do
    expect(described_class.dk_parts("NTRF+116")).to include(text_key: nil)
  end
end
