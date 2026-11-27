# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# A person's family links on a page of their own
# (/people/:person_id/family_members/edit): for the privileged view and the
# unit leaders of the person's unit (:update_family).
describe Person::FamilyMembersController, type: :controller do
  let(:yp) { people(:yp_a_1) }
  let(:sibling) { people(:yp_a_2) }

  def link_params = {family_members_attributes: {"0" => {other_id: sibling.id, kind: "sibling", label: "Zwilling"}}}

  describe "who may edit the family" do
    it "is the unit leader of the person's unit and the privileged view" do
      expect(Ability.new(people(:ul_a_1).reload).can?(:update_family, yp)).to be(true)
      expect(Ability.new(people(:admin)).can?(:update_family, yp)).to be(true)
    end

    it "is not the unit leader of another unit, nor the person themselves" do
      expect(Ability.new(people(:ul_b_1).reload).can?(:update_family, yp)).to be(false)
      expect(Ability.new(yp).can?(:update_family, yp)).to be(false)
    end
  end

  it "saves the links of the unit leader, both ways" do
    sign_in(people(:ul_a_1))
    put :update, params: {person_id: yp.id, person: link_params}

    expect(response).to redirect_to("/people/#{yp.id}")
    expect(FamilyMember.find_by(person: yp, other: sibling)&.label).to eq("Zwilling")
    expect(FamilyMember.find_by(person: sibling, other: yp)).to be_present
  end

  it "lets the unit leader change the kind of an existing link" do
    link = FamilyMember.create!(person: yp, other: sibling, kind: "sibling")
    sign_in(people(:ul_a_1))

    put :update, params: {person_id: yp.id, person: {family_members_attributes: {
      "0" => {id: link.id, kind: "parent"}
    }}}
    expect(link.reload.kind).to eq("parent")
    expect(FamilyMember.find_by(person: sibling, other: yp).kind).to eq("child")
  end

  it "shows a form error when two existing families would be linked" do
    FamilyMember.create!(person: yp, other: people(:ul_a_1), kind: "sibling")
    FamilyMember.create!(person: sibling, other: people(:ul_a_2), kind: "sibling")
    sign_in(people(:admin))

    put :update, params: {person_id: yp.id, person: {family_members_attributes: {
      "9" => {other_id: sibling.id, kind: "spouse"}
    }}}

    expect(response).to have_http_status(422)
    expect(assigns(:person).errors.full_messages.join).to include("gehören schon zu verschiedenen Familien")
    expect(FamilyMember.where(person: yp, other: sibling)).to be_empty
  end

  describe "the edit page" do
    render_views

    it "lets the unit leader change the inverse label of an existing link" do
      link = FamilyMember.create!(person: yp, other: sibling, kind: "relative", label: "Tante", inverse_label: "Nichte")
      sign_in(people(:ul_a_1))
      get :edit, params: {person_id: yp.id}
      expect(Capybara.string(response.body)).to have_css("input[name$='[inverse_label]'][value='Nichte']")

      put :update, params: {person_id: yp.id, person: {family_members_attributes: {
        "0" => {id: link.id, kind: "relative", label: "Tante", inverse_label: "Großnichte"}
      }}}
      expect(FamilyMember.find_by(person: sibling, other: yp).label).to eq("Großnichte")
    end

    it "shows a link with its kind and the relative, and asks before removing it, naming the relation both ways",
      :aggregate_failures do
      yp.update_columns(gender: "w")
      sibling.update_columns(gender: "m")
      FamilyMember.create!(person: yp, other: sibling, kind: "sibling")
      sign_in(people(:ul_a_1))
      get :edit, params: {person_id: yp.id}

      page = Capybara.string(response.body)
      link = page.find("a.remove_nested_fields[data-wsjrdp-confirm]")
      expect(link).to have_css("i.fa-trash-alt")
      question = link["data-wsjrdp-confirm"]
      expect(question).to include("Familienbeziehung entfernen?",
        "#{sibling.short_full_name_with_nickname} ist Bruder von #{yp.short_full_name_with_nickname}.",
        "#{yp.short_full_name_with_nickname} ist Schwester von #{sibling.short_full_name_with_nickname}.",
        "Beide Richtungen werden beim Speichern gelöscht.")
      expect(page).to have_css("a.add_nested_fields[data-association='family_members']",
        text: "Familienmitglied hinzufügen")
      expect(page).to have_no_css("label", text: "Familienmitglieder")
      expect(page).to have_css("select[name$='[kind]'] option[selected][value='sibling']")
      expect(page).to have_css("span.text-muted", text: sibling.wsjrdp_role)
      expect(page).to have_css("strong a", text: sibling.short_full_name_with_nickname)
    end
  end

  describe "a link to a relative the unit leader may not see" do
    render_views

    let(:relative) { people(:yp_b_1) }
    let!(:link) { FamilyMember.create!(person: yp, other: relative, kind: "sibling", label: "Cousine") }

    before { sign_in(people(:ul_a_1)) }

    it "shows the row disabled, without a remove link" do
      expect(Ability.new(people(:ul_a_1).reload).can?(:show, relative)).to be(false)
      get :edit, params: {person_id: yp.id}

      row = Capybara.string(response.body).all("#family_members_fields .fields")
        .find { |fields| fields.has_css?("input[value='#{link.id}']", visible: :all) }
      expect(row).to have_css("select[name$='[kind]'][disabled]")
      expect(row).to have_css("input[name$='[label]'][disabled]")
      expect(row).to have_css("input[name$='[inverse_label]'][disabled]")
      expect(row).to have_no_css("a.remove_nested_fields")
      expect(row).to have_css("span.remove_nested_fields_disabled")
    end

    it "changes and removes nothing of it, even when sent" do
      put :update, params: {person_id: yp.id, person: {family_members_attributes: {
        "0" => {id: link.id, kind: "parent", label: "Mutter", _destroy: "1"},
        "1" => {other_id: people(:ul_b_1).id, kind: "sibling"}
      }}}

      expect(link.reload).to have_attributes(kind: "sibling", label: "Cousine")
      expect(FamilyMember.where(person: yp, other: people(:ul_b_1))).to be_empty
    end
  end

  it "keeps the person themselves out" do
    sign_in(yp)

    expect { get :edit, params: {person_id: yp.id} }.to raise_error(CanCan::AccessDenied)
    expect { put :update, params: {person_id: yp.id, person: link_params} }.to raise_error(CanCan::AccessDenied)
    expect(FamilyMember.where(person: yp)).to be_empty
  end
end
