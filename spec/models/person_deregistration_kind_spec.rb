# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Who ended the participation: the person ("Abmeldung") or the contingent
# ("Kündigung"). The key is absent for everyone who was there before the flag
# existed, so the absent value has to read as a withdrawal.
describe "Person deregistration kind" do
  let(:person) { people(:yp_a_1) }

  it "reads an absent value as a withdrawal" do
    expect(person.additional_info).not_to have_key("deregistration_kind")
    expect(person.deregistration_kind).to be_nil
    expect(person.deregistration_kind_or_default).to eq("withdrawal")
    expect(person).not_to be_deregistration_termination
  end

  it "keeps an explicit withdrawal as it was written" do
    person.update!(deregistration_kind: "withdrawal")

    expect(person.reload.deregistration_kind).to eq("withdrawal")
    expect(person.deregistration_kind_or_default).to eq("withdrawal")
    expect(person).not_to be_deregistration_termination
  end

  it "reads a termination as one" do
    person.update!(deregistration_kind: "termination")

    expect(person.reload.deregistration_kind).to eq("termination")
    expect(person.deregistration_kind_or_default).to eq("termination")
    expect(person).to be_deregistration_termination
  end

  it "rejects a value outside the two kinds" do
    person.deregistration_kind = "foo"

    expect(person).not_to be_valid
    expect(person.errors[:deregistration_kind]).to be_present
  end

  it "drops the key when the value is blanked" do
    person.update!(deregistration_kind: "termination")

    person.update!(deregistration_kind: "")

    expect(person.reload.additional_info).not_to have_key("deregistration_kind")
    expect(person.deregistration_kind_or_default).to eq("withdrawal")
  end
end
