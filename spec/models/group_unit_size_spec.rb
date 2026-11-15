# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# A unit's size at the Unit-Einteilung, the size it is to have and its number
# of unit leaders and of patrols, stored in additional_info where they differ
# from the rule (40, 40, 4 and 4).
describe Group do
  let(:unit) { groups(:unit_a) }

  it "answers the rule while nothing is stored" do
    expect(unit.initial_unit_size).to be_nil
    expect(unit.expected_unit_size).to be_nil
    expect(unit.expected_ul_number).to be_nil
    expect(unit.effective_initial_unit_size).to eq(40)
    expect(unit.effective_expected_unit_size).to eq(40)
    expect(unit.effective_expected_ul_number).to eq(4)
    expect(unit.expected_patrol_number).to be_nil
    expect(unit.effective_expected_patrol_number).to eq(4)
  end

  it "stores the values as integers in additional_info, and blank removes them again" do
    unit.update!(initial_unit_size: "38", expected_unit_size: "42", expected_ul_number: "3",
      expected_patrol_number: "5")

    unit.reload
    expect(unit.additional_info).to include("initial_unit_size" => 38, "expected_unit_size" => 42,
      "expected_ul_number" => 3, "expected_patrol_number" => 5)
    expect(unit.effective_expected_patrol_number).to eq(5)
    expect(unit.effective_initial_unit_size).to eq(38)
    expect(unit.effective_expected_unit_size).to eq(42)
    expect(unit.effective_expected_ul_number).to eq(3)

    unit.update!(initial_unit_size: "", expected_unit_size: "", expected_ul_number: "", expected_patrol_number: "")

    unit.reload
    expect(unit.additional_info.keys).not_to include("initial_unit_size", "expected_unit_size", "expected_ul_number",
      "expected_patrol_number")
    expect(unit.effective_initial_unit_size).to eq(40)
    expect(unit.effective_expected_unit_size).to eq(40)
  end

  it "knows the day the unit was formed, the rule while nothing is stored" do
    expect(unit.effective_unit_formed_date).to eq(Date.new(2026, 1, 7))

    unit.update!(unit_formed_date: "14.01.2026")

    unit.reload
    expect(unit.additional_info["unit_formed_date"]).to eq("2026-01-14")
    expect(unit.unit_formed_date).to eq(Date.new(2026, 1, 14))
    expect(unit.effective_unit_formed_date).to eq(Date.new(2026, 1, 14))
  end

  it "refuses what is not a whole number" do
    unit.initial_unit_size = "-1"
    unit.expected_unit_size = "1,5"
    unit.expected_ul_number = "zwei"
    unit.expected_patrol_number = "-3"

    expect(unit).not_to be_valid
    expect(unit.errors.attribute_names).to include(:initial_unit_size, :expected_unit_size, :expected_ul_number,
      :expected_patrol_number)
  end
end

describe GroupsController, type: :controller do
  render_views

  let(:unit) { groups(:unit_a) }
  let(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }

  it "shows both on the group's info, the rule where nothing is stored" do
    unit.update!(expected_ul_number: 5)
    sign_in(admin)

    get :show, params: {id: unit.id}

    text = Nokogiri::HTML(response.body).text.squish
    expect(text).to include("Unit-Größe bei Einteilung 40 (Regel, nicht gesetzt)",
      "Unit-Größe (Soll) 40 (Regel, nicht gesetzt)", "Anzahl Unit Leader (Soll) 5",
      "Anzahl Patrols (Soll) 4 (Regel, nicht gesetzt)",
      "Unit eingeteilt am 07.01.2026 (Regel, nicht gesetzt)")
  end

  it "saves both for whoever may edit the unit code" do
    sign_in(admin)

    patch :update, params: {id: unit.id, group: {unit_code: "#123456", initial_unit_size: "39", expected_unit_size: "41",
                                                 expected_ul_number: "5", expected_patrol_number: "3", unit_formed_date: "10.01.2026"}}

    unit.reload
    expect([unit.unit_code, unit.initial_unit_size, unit.expected_unit_size, unit.expected_ul_number,
      unit.expected_patrol_number, unit.unit_formed_date]).to eq(["#123456", 39, 41, 5, 3, Date.new(2026, 1, 10)])
  end
end
