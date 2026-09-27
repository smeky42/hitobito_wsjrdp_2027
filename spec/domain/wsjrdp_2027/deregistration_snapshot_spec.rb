# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The person's data as the first made document of a deregistration captured
# it: bank account and address, role, team or unit.
describe Wsjrdp2027::DeregistrationSnapshot do
  let(:person) { people(:yp_a_1) }

  before do
    allow(Geocoder).to receive(:search).and_return([])
    person.update!(sepa_name: "Kim Muster", sepa_iban: "DE02120300000000202051",
      sepa_address: "Musterweg 1, 12345 Musterstadt")
  end

  it "reads the current values while nothing is captured" do
    snapshot = described_class.for(person.reload)

    expect(snapshot).not_to be_stored
    expect(snapshot.role).to eq("YP")
    expect(snapshot.sepa.sepa_iban).to eq("DE02120300000000202051")
  end

  it "captures once and keeps what it captured" do
    described_class.for(person.reload).capture!
    person.save!
    person.reload.update!(sepa_iban: "DE89370400440532013000")

    snapshot = described_class.for(person.reload)
    expect(snapshot).to be_stored
    expect(snapshot.sepa.sepa_iban).to eq("DE02120300000000202051")

    snapshot.capture!
    expect(person.deregistration_refund_iban).to eq("DE02120300000000202051")
  end

  # The account a refund goes to lives in the refund_* keys, the role, its name
  # and the team or unit in the person_* keys.
  it "keeps the account in the refund keys and the rest in the person keys" do
    described_class.for(person.reload).capture!
    person.save!
    record = person.reload.additional_info["deregistration_record"]

    expect(record["refund_account_holder"]).to eq("Kim Muster")
    expect(record["refund_iban"]).to eq("DE02120300000000202051")
    expect(record["refund_sepa_address"]).to eq("Musterweg 1, 12345 Musterstadt")
    expect(record).not_to have_key("refund_bic")
    expect(record["person_role"]).to eq("YP")
    expect(record).to have_key("person_role_name")
    expect(record).not_to have_key("snapshot")
  end

  it "forgets everything with clear!" do
    described_class.for(person.reload).capture!
    person.save!

    described_class.for(person.reload).clear!
    person.save!

    expect(person.reload.additional_info).not_to have_key("deregistration_record")
  end
end
