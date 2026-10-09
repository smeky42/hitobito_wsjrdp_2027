# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"
require Rails.root.join("..", "hitobito_wsjrdp_2027", "db", "migrate", "20261006200006_add_contract_columns_to_people.rb")

# The participation contract (contract_status and its dates), apart from
# status: started by the first confirmation, ended by a deregistration after
# one, untouched by every step back in between.
describe Person, "contract" do
  let(:person) { people(:yp_a_1) }
  let(:finance) { people(:admin) }

  def change_status(status)
    person.update!(status: status)
    person.reload
  end

  it "has no contract before the confirmation" do
    expect(person).to have_attributes(contract_status: "none", contract_confirmed_at: nil, contract_ended_at: nil)
    change_status("reviewed")
    expect(person.contract_status).to eq "none"
  end

  it "is confirmed by the confirmation, with its time and the author the caller sets" do
    travel_to(Time.zone.local(2026, 10, 9, 12)) do
      person.update!(status: "confirmed", contract_confirmed_by: finance)
    end

    expect(person.reload).to have_attributes(contract_status: "confirmed", contract_ended_at: nil,
      contract_confirmed_at: Time.zone.local(2026, 10, 9, 12), contract_confirmed_by: finance)
  end

  it "has no author when the caller sets none, not the one of the earlier contract" do
    person.update!(status: "confirmed", contract_confirmed_by: finance)
    change_status("deregistered")
    PaperTrail.request(whodunnit: finance.id.to_s) { change_status("confirmed") }

    expect(person).to have_attributes(contract_status: "confirmed", contract_confirmed_by: nil)
  end

  it "stays confirmed through a step back and keeps the first confirmation" do
    travel_to(Time.zone.local(2026, 1, 5)) { change_status("confirmed") }
    change_status("upload")
    expect(person.contract_status).to eq "confirmed"
    change_status("deregistration_noted")
    expect(person.contract_status).to eq "confirmed"

    travel_to(Time.zone.local(2026, 3, 1)) { change_status("confirmed") }
    expect(person.contract_confirmed_at).to eq Time.zone.local(2026, 1, 5)
  end

  it "is ended by a deregistration after the confirmation" do
    change_status("confirmed")
    travel_to(Time.zone.local(2026, 9, 30)) { change_status("deregistered") }

    expect(person).to have_attributes(contract_status: "ended", contract_ended_at: Time.zone.local(2026, 9, 30))
    expect(person.contract_confirmed_at).to be_present
  end

  it "has none after a deregistration without a confirmation" do
    change_status("deregistered")
    expect(person.contract_status).to eq "none"
  end

  it "stays ended through steps forward until confirmed again" do
    change_status("confirmed")
    change_status("deregistered")
    change_status("reviewed")
    expect(person.contract_status).to eq "ended"
  end

  it "starts anew when confirmed again after the end" do
    change_status("confirmed")
    change_status("deregistered")
    travel_to(Time.zone.local(2026, 10, 1)) { change_status("confirmed") }

    expect(person).to have_attributes(contract_status: "confirmed", contract_ended_at: nil,
      contract_confirmed_at: Time.zone.local(2026, 10, 1))
  end

  it "logs the contract with the status" do
    with_versioning { person.update!(status: "confirmed") }

    expect(person.versions.reorder(:id).last.changeset.keys).to include("status", "contract_status",
      "contract_confirmed_at")
  end

  describe "the fill from versions" do
    def replay(*statuses)
      rows = statuses.each_with_index.map do |(from, to), i|
        [person.id, Time.zone.local(2026, 1, 1 + i).to_s,
          Wsjrdp2027::PaperTrail::YamlSerializer.dump({"status" => [from, to]})]
      end
      AddContractColumnsToPeople.new.send(:replay, rows)
    end

    it "takes the first confirmation, recorded as confirmed by person 65" do
      contract = replay(%w[reviewed confirmed], %w[confirmed upload], %w[upload confirmed])

      expect(contract).to include(contract_status: "confirmed", contract_confirmed_by_id: 65,
        contract_confirmed_by_type: "Person", contract_ended_at: nil)
      expect(contract[:contract_confirmed_at]).to eq Time.zone.local(2026, 1, 1).to_s
    end

    it "ends with the deregistration after the confirmation, not before" do
      expect(replay(%w[registered deregistered])[:contract_status]).to eq "none"
      ended = replay(%w[reviewed confirmed], %w[confirmed deregistration_noted],
        %w[deregistration_noted deregistered])
      expect(ended).to include(contract_status: "ended", contract_ended_at: Time.zone.local(2026, 1, 3).to_s)
    end

    it "ignores other changes and status changes to nothing" do
      contract = replay(["reviewed", "confirmed"], ["confirmed", nil], %w[confirmed deregistration_noted],
        %w[deregistration_noted reviewed])
      expect(contract[:contract_status]).to eq "confirmed"
    end
  end
end
