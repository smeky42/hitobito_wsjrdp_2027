# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# A family link in the person's log names the other person as the person
# page does: the role muted and smaller, the name linked where the viewer may
# see that person, the relation behind it.
describe Person::LogController do
  render_views

  let(:person) { people(:yp_a_1) }
  let(:other) { people(:yp_a_2) }

  def change_lines = Nokogiri::HTML(response.body).css(".log-infos div")

  it "names the other person with role, link and relation" do
    with_versioning { FamilyMember.create!(person: person, other: other, kind: "sibling", label: "Zwilling") }
    sign_in(people(:admin))

    get(:index, params: {group_id: person.primary_group_id, id: person.id})

    line = change_lines.find { |div| div.text.include?("Familienmitglied verknüpft") }
    expect(line.text.squish).to eq("Familienmitglied verknüpft: #{other.wsjrdp_role}" \
      "#{other.short_full_name_with_nickname} (Zwilling).")
    expect(line.at_css("span.small.text-muted").text).to eq(other.wsjrdp_role)
    expect(line.at_css("a")["href"]).to eq("/people/#{other.id}")
  end

  it "names the other person without a link where the viewer may not see them" do
    hidden = Fabricate(:person, first_name: "Ohne", last_name: "Rolle")
    with_versioning { FamilyMember.create!(person: person, other: hidden, kind: "relative") }
    viewer = people(:admin)
    sign_in(viewer)
    expect(Ability.new(viewer).can?(:show, hidden)).to be(false)

    get(:index, params: {group_id: person.primary_group_id, id: person.id})

    line = change_lines.find { |div| div.text.include?("Familienmitglied verknüpft") }
    expect(line.text).to include(hidden.short_full_name_with_nickname)
    expect(line.at_css("a")).to be_nil
  end
end
