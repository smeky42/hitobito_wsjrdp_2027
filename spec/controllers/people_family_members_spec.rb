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
  render_views

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
    before { FamilyMember.create!(person: yp, other: sibling, kind: :sibling) }

    def family_section
      Capybara.string(response.body).all("section", text: "Andere Familienmitglieder").last
    end

    it "lists the family with muted role, linked name and relation for the privileged view" do
      sign_in(people(:admin))
      get :show, params: {group_id: yp.primary_group_id, id: yp.id}

      row = family_section.find("table tr")
      expect(row).to have_css("span.text-muted:not(.fw-light)", text: sibling.wsjrdp_role)
      expect(row).to have_css("strong a", text: sibling.short_full_name_with_nickname)
      expect(row).to have_css("span.text-muted.fw-light", text: "Geschwister")
      expect(row).to have_no_css("strong span.text-muted")
    end

    it "shows the family to the person themselves, linking only whom they may see" do
      sign_in(yp)
      get :show, params: {group_id: yp.primary_group_id, id: yp.id}

      expect(Ability.new(yp).can?(:show, sibling)).to be(false)
      row = family_section.find("table tr")
      expect(row).to have_css("strong", text: sibling.short_full_name_with_nickname)
      expect(row).to have_no_css("a", text: sibling.short_full_name_with_nickname)
    end

    it "lists parents before siblings and children" do
      FamilyMember.where(person: [yp, sibling]).delete_all
      FamilyMember.create!(person: yp, other: people(:ul_a_1), kind: "child")
      FamilyMember.create!(person: yp, other: people(:admin), kind: "parent")
      sign_in(people(:admin))
      get :show, params: {group_id: yp.primary_group_id, id: yp.id}

      kinds = family_section.all("table tr").map { |tr| tr.all("span.fw-light").map(&:text).first }
      expect(kinds).to eq(%w[Elternteil Kind])
    end

    it "names the relation by its own name where there is one" do
      FamilyMember.find_by(person: yp, other: sibling).update!(label: "Zwilling")
      sign_in(people(:admin))
      get :show, params: {group_id: yp.primary_group_id, id: yp.id}

      expect(family_section.find("table tr")).to have_css("span.fw-light", text: "Zwilling")
    end

    it "lists the household the same way: muted role, bold name" do
      [yp, sibling].each { |p| p.update_columns(household_key: "denzer") }
      sign_in(people(:admin))
      get :show, params: {group_id: yp.primary_group_id, id: yp.id}

      household = Capybara.string(response.body).all("turbo-frame#household_aside section").first
      row = household.all("table tr").find { |tr| tr.has_text?(sibling.short_full_name_with_nickname) }
      expect(row).to have_css("span.text-muted", text: sibling.wsjrdp_role)
      expect(row).to have_css("strong a", text: sibling.short_full_name_with_nickname)
    end

    it "names people by their short name with the nickname, not the full one" do
      sibling.update_columns(first_name: "Franz Ole", nickname: "Ole", last_name: "Mast")
      [yp, sibling].each { |p| p.update_columns(household_key: "mast") }
      sign_in(people(:admin))
      get :show, params: {group_id: yp.primary_group_id, id: yp.id}

      page = Capybara.string(response.body)
      expect(page.all("li.chip a", text: "Ole Mast")).not_to be_empty
      expect(family_section.find("table tr")).to have_css("strong a", text: "Ole Mast")
      expect(page.all("li.chip, section table").map(&:text).join).not_to include("Franz Ole Mast")
    end

    it "lists the family as chips under the contact data, with the relation" do
      sign_in(people(:admin))
      get :show, params: {group_id: yp.primary_group_id, id: yp.id}

      block = Capybara.string(response.body).all(".contactable .wsjrdp-household-attrs")
        .find { |div| div.has_css?("small", text: "Andere Familienmitglieder") }
      chip = block.find("li.chip")
      expect(chip).to have_css("span.small.text-muted", text: sibling.wsjrdp_role)
      expect(chip).to have_css("a", text: sibling.short_full_name_with_nickname)
      expect(chip).to have_css("span.fw-light", text: "Geschwister")
    end

    it "links the edit pages of household and family from their captions, for who may edit" do
      [yp, sibling].each { |p| p.update_columns(household_key: "denzer") }
      sign_in(people(:admin))
      get :show, params: {group_id: yp.primary_group_id, id: yp.id}

      page = Capybara.string(response.body)
      expect(page).to have_css(".contactable a.wsjrdp-household-edit[href='/people/#{yp.id}/family_members/edit']")
      expect(page).to have_css(".contactable a.wsjrdp-household-edit[href$='/people/#{yp.id}/household/edit']")
    end

    it "shows no edit icon to the person themselves" do
      sign_in(yp)
      get :show, params: {group_id: yp.primary_group_id, id: yp.id}

      expect(Capybara.string(response.body)).to have_no_css("a[href='/people/#{yp.id}/family_members/edit']")
    end

    it "puts the role before each household chip under the contact data" do
      [yp, sibling].each { |p| p.update_columns(household_key: "denzer") }
      sign_in(people(:admin))
      get :show, params: {group_id: yp.primary_group_id, id: yp.id}

      chip = Capybara.string(response.body).all("li.chip").find { |li| li.has_text?(sibling.short_full_name_with_nickname) }
      expect(chip).to have_css("span.small.text-muted", text: sibling.wsjrdp_role)
      expect(chip).to have_css("a", text: sibling.short_full_name_with_nickname)
    end

    it "leaves the section out without family members" do
      FamilyMember.where(person: [yp, sibling]).delete_all
      sign_in(yp)
      get :show, params: {group_id: yp.primary_group_id, id: yp.id}

      expect(family_section).to be_nil
    end
  end
end
