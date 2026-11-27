# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Fin::ReturnOriginals do
  include_context "payment area"

  let(:transfer) do
    returned_transfer(cdtr_iban: "BE79967040785533", value_date: Date.new(2026, 5, 6))
  end
  let!(:sent) do
    camt_return(-150, bank_transaction_code: "PMNT+ICDT+ESCT", return_reason: nil, endtoend_id: nil,
      cdtr_iban: "BE79967040785533", value_date: Date.new(2026, 4, 28), description: "Überweisung")
  end
  let(:other_amount) do
    camt_return(-120, bank_transaction_code: "PMNT+ICDT+ESCT", return_reason: nil, endtoend_id: nil,
      value_date: Date.new(2026, 4, 28))
  end

  it "proposes the sent transfer of the same amount, with what matched" do
    other = other_amount
    candidates = described_class.candidates(transfer.reload)

    expect(candidates.map(&:id)).to eq([sent.id])
    expect(candidates.first.matches).to eq([:iban])
    expect(described_class.candidate?(transfer, other)).to be(false)
  end

  it "links the original both ways and unlinks it again" do
    described_class.link!(transfer, sent)
    expect([transfer.reload.reverses_id, sent.reload.reversed_by_id]).to eq([sent.id, transfer.id])

    described_class.unlink!(transfer)
    expect([transfer.reload.reverses_id, sent.reload.reversed_by_id]).to eq([nil, nil])
  end
end
