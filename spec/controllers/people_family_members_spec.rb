# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Siblings (FamilyMember) on a person: only the privileged view (:log) links
# them through the person form, and only it sees them on the person's page.
describe PeopleController, type: :controller do
  let(:yp) { people(:yp_a_1) }
  let(:sibling) { people(:admin) }

  def link_params = {family_members_attributes: {"0" => {other_id: sibling.id, kind: "sibling"}}}

  def update_as(user)
    sign_in(user)
    put :update, params: {group_id: yp.primary_group_id, id: yp.id, person: link_params}
  end

  it "ignores sibling links a participant sends for their own profile" do
    expect(Ability.new(yp).can?(:log, yp)).to be(false)

    update_as(yp)

    expect(FamilyMember.where(person: yp)).to be_empty
    expect(sibling.reload.family_key).to be_nil
  end

  it "links siblings for the privileged view" do
    expect(Ability.new(people(:admin)).can?(:log, yp)).to be(true)

    update_as(people(:admin))

    expect(FamilyMember.where(person: yp, other: sibling)).to exist
    expect(FamilyMember.where(person: sibling, other: yp)).to exist
  end

  it "saves own names of the relation for the privileged view" do
    sign_in(people(:admin))
    put :update, params: {group_id: yp.primary_group_id, id: yp.id, person: {family_members_attributes: {
      "0" => {other_id: sibling.id, kind: "relative", label: "Onkel", inverse_label: "Neffe"}
    }}}

    expect(FamilyMember.find_by(person: yp, other: sibling).label).to eq("Onkel")
    expect(FamilyMember.find_by(person: sibling, other: yp).label).to eq("Neffe")
  end

  it "leaves a link to a relative the unit leader may not see as it is, in the person form" do
    link = FamilyMember.create!(person: yp, other: people(:yp_b_1), kind: "sibling")
    sign_in(people(:ul_a_1))
    put :update, params: {group_id: yp.primary_group_id, id: yp.id, person: {family_members_attributes: {
      "0" => {id: link.id, kind: "parent", _destroy: "1"}
    }}}

    expect(response).to be_redirect
    expect(link.reload.kind).to eq("sibling")
  end

  describe "the person's form" do
    render_views

    # Without siblings yet the block is the "Eintrag hinzufügen" link; its
    # fields come from a blueprint.
    def family_fields = Capybara.string(response.body).all("a.add_nested_fields[data-association='family_members']")

    it "offers the sibling fields to the privileged view" do
      sign_in(people(:admin))
      get :edit, params: {group_id: yp.primary_group_id, id: yp.id}

      expect(family_fields).not_to be_empty
    end

    it "leaves them out of the person's own form" do
      sign_in(yp)
      get :edit, params: {group_id: yp.primary_group_id, id: yp.id}

      expect(response).to have_http_status(:ok)
      expect(family_fields).to be_empty
    end
  end

  describe "the person's page" do
    render_views

    def page = Capybara.string(response.body)

    def family_section = page.all("section", text: "Andere Familienmitglieder").last

    it "lists family and household for the privileged view: short names linked, the own relation name, the edit links" do
      sibling.update_columns(first_name: "Franz Ole", nickname: "Ole", last_name: "Mast")
      [yp, sibling].each { |p| p.update_columns(household_key: "mast") }
      FamilyMember.create!(person: yp, other: sibling, kind: :sibling, label: "Zwilling")
      sign_in(people(:admin))
      get :show, params: {group_id: yp.primary_group_id, id: yp.id}

      row = family_section.find("table tr")
      expect(row).to have_css("a", text: "Ole Mast")
      expect(row).to have_text("Zwilling")
      expect(row).to have_text(sibling.wsjrdp_role)
      household = page.all("turbo-frame#household_aside section").first
      expect(household.all("table tr").find { |tr| tr.has_text?("Ole Mast") }).to have_css("a", text: "Ole Mast")
      expect(page.all("li.chip a", text: "Ole Mast")).not_to be_empty
      expect(page.all("li.chip, section table").map(&:text).join).not_to include("Franz Ole Mast")
      expect(page).to have_css(".contactable a[href='/people/#{yp.id}/family_members/edit']")
      expect(page).to have_css(".contactable a[href$='/people/#{yp.id}/household/edit']")
    end
  end
end
