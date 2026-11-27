# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Kontingent > Units: one row per WSJRDP unit with people whose contract is in
# force, narrowed by the Schnellauswahl; a row opens the unit's people. Visible
# like the IST tab: only to whoever may see the contingent's people.
describe Contingent::WsjrdpUnitsController, type: :controller do
  def unit_person(nickname, contract_status:, status:, group: groups(:unit_a), role: Group::Unit::Member)
    person = Fabricate(role.name.to_sym, group: group).person
    person.update_columns(primary_group_id: group.id, nickname: nickname, contract_status: contract_status,
      status: status)
    person
  end

  # Unit A holds Ba, Bb and Oa with a contract in force, Ca and Cb in Abmeldung.
  before_all(setup_fixtures: true) do
    Person.where(primary_group_id: groups(:unit_a).id).update_all(contract_status: "none", status: "registered")
    unit_person("Ba", contract_status: "confirmed", status: "confirmed")
    unit_person("Bb", contract_status: "confirmed", status: "confirmed")
    unit_person("Oa", contract_status: "confirmed", status: "reviewed")
    unit_person("Ca", contract_status: "confirmed", status: "deregistration_noted")
    unit_person("Cb", contract_status: "none", status: "deregistration_noted")
  end

  let(:unit_a) { groups(:unit_a) }

  before { sign_in(people(:cmt_leader)) }

  # A unit with `in_force` people whose contract is in force, and `cancelling`
  # in Abmeldung.
  def unit_with_people(name, in_force: 1, cancelling: 0)
    unit = Fabricate(Group::Unit.name.to_sym, parent: groups(:root), name: name)
    in_force.times { unit_person(nil, contract_status: "confirmed", status: "confirmed", group: unit) }
    cancelling.times do
      unit_person(nil, contract_status: "confirmed", status: "deregistration_noted", group: unit)
    end
    unit
  end

  def shown_units = controller.send(:unit_rows).page.map(&:name)

  def shown_nicknames
    ids = controller.send(:unit_people_rows).page.map(&:id)
    Person.where(id: ids).index_by(&:id).values_at(*ids).map(&:nickname)
  end

  describe "GET index" do
    it "lists the WSJRDP units with people in force only, in a natural order of their names" do
      groups(:unit_b).update_columns(is_wsjrdp: false)
      unit_with_people("A10")
      unit_with_people("A2")
      unit_with_people("A3", in_force: 0, cancelling: 1)

      get :index

      expect(shown_units).not_to include("Unit B", "Empty Unit", "A3")
      expect(shown_units & %w[A2 A10]).to eq(%w[A2 A10])
    end

    it "shows the movements by day, the view Verlauf, by default" do
      get :index

      expect(controller.send(:unit_rows).state.view).to eq("history")
    end

    describe "the Schnellauswahl" do
      it "narrows the list to a series" do
        unit_with_people("A1")
        unit_with_people("B1")

        get :index, params: {unf: "!(!(!(se,in,'A')))"}

        expect(shown_units).to eq(%w[A1])
      end

      # The size the unit is to have, not the one at the Unit-Einteilung.
      it "narrows the list to the units whose people in force are not as many as they are to be" do
        unit_with_people("A1").update!(expected_unit_size: 1, initial_unit_size: 2)
        unit_with_people("A2", in_force: 2).update!(expected_unit_size: 1, initial_unit_size: 2)

        get :index, params: {unf: "!(!(!(ch,in,'1')))"}

        expect(shown_units).to include("A2")
        expect(shown_units).not_to include("A1")
      end

      it "narrows the list to the units with open deregistrations, in a series" do
        unit_with_people("A1", cancelling: 1)
        unit_with_people("B1")
        unit_with_people("B2", cancelling: 1)

        get :index, params: {unf: "!(!(!(se,in,'B')),!(!(ch,in,'2')))"}

        expect(shown_units).to eq(%w[B2])
      end

      it "narrows the list to the units whose patrols are incomplete" do
        Person.where(primary_group_id: unit_a.id).update_all(patrol: "A")
        unit_with_people("P2")

        get :index, params: {unf: "!(!(!(ch,in,'3')))"}

        expect(shown_units).to include("P2")
        expect(shown_units).not_to include("Unit A")
      end
    end

    it "is refused to an eHoC, who may not see the people" do
      sign_in(Fabricate(Group::Root::ExtendedHeadOfContingent.name.to_sym, group: groups(:root)).person)

      expect { get :index }.to raise_error(CanCan::AccessDenied)
      expect { get :show, params: {id: unit_a.id} }.to raise_error(CanCan::AccessDenied)
    end
  end

  describe "GET show" do
    it "lists a unit's people in their natural order and counts who is leaving" do
      unit_person("De", contract_status: "ended", status: "deregistered")

      get :show, params: {id: unit_a.id}

      expect(shown_nicknames.first(2)).to match_array(%w[Ca Cb])
      expect(shown_nicknames.last).to eq("De")
      expect(controller.send(:unit_people_summary)).to end_with("+ 2 in Abmeldung + 1 abgemeldet")
    end

    it "narrows a unit's people by the bare patrol letter" do
      Person.where(nickname: "Ba").update_all(patrol: "A")

      get :show, params: {id: unit_a.id, upf: "!(!(!(pt,in,'A')))"}

      expect(shown_nicknames).to eq(%w[Ba])
    end

    it "narrows a unit's people to those without a patrol" do
      Person.where(nickname: "Ba").update_all(patrol: "A")

      get :show, params: {id: unit_a.id, upf: "!(!(!(pt,in,'none')))"}

      expect(shown_nicknames).to include("Bb", "Oa")
      expect(shown_nicknames).not_to include("Ba")
      expect(Wsjrdp2027::ContingentUnitPeopleFilterSchema::PATROL_OPTIONS.pairs.map(&:first))
        .to eq(%w[none A B C D])
    end

    it "narrows a unit's people by role" do
      unit_person("Zz", contract_status: "confirmed", status: "confirmed", role: Group::Unit::Leader)

      get :show, params: {id: unit_a.id, upf: "!(!(!(ro,in,'UL')))"}

      expect(shown_nicknames).to include("Zz")
      expect(shown_nicknames).not_to include("Ba", "Ca")
    end

    it "narrows a unit's people by contract" do
      get :show, params: {id: unit_a.id, upf: "!(!(!(vs,in,'cancel')))"}

      expect(shown_nicknames).to match_array(%w[Ca Cb])
    end

    describe "whoever left the unit for another one" do
      before do
        moved = unit_person("Mv", contract_status: "confirmed", status: "confirmed")
        moved.roles.where(group_id: unit_a.id).update_all(start_on: Date.new(2026, 1, 7), end_on: Date.new(2026, 3, 1))
        Fabricate(Group::Unit::Member.name.to_sym, group: groups(:unit_b), person: moved, start_on: Date.new(2026, 3, 2))
        moved.update_columns(primary_group_id: groups(:unit_b).id)
      end

      it "is left out by default" do
        get :show, params: {id: unit_a.id}

        expect(shown_nicknames).not_to include("Mv")
      end

      it "is shown last on demand" do
        get :show, params: {id: unit_a.id, upu: "moved.shown"}

        expect(shown_nicknames.last).to eq("Mv")
      end
    end

    it "shows the default columns, Haushalt too, also to whoever remembered a choice made before it existed" do
      session["wsjrdp_table_state"] = {"contingent/wsjrdp_units#show|up" => {"c" => "p,ca,c,s,cs,js,~r,~ro,~pt"}}

      get :show, params: {id: unit_a.id}

      expect(controller.send(:unit_people_table_state).visible_column_keys)
        .to eq(%w[role person patrol contract status cancel budget])
    end
  end

  it "applies a unit's people filter back into the unit" do
    post :apply, params: {id: unit_a.id, expandable_table_level: 1,
                          filter_json: [[["wsjrdp_role", "in", "UL"]]].to_json}

    expect(response).to have_http_status(:see_other)
    expect(response.location).to start_with("http://test.host/contingent/units/#{unit_a.id}?")
    expect(response.location).to include("expandable_table_level=1", "upf=")
  end
end
