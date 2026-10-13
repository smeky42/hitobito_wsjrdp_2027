# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The person log writes the answers of "Daten für den Veranstalter" as stored,
# with the label the forms show in brackets (true [Langarm]), through
# Wsjrdp2027::PaperTrail::VersionDecorator#attribute_change.
describe Person::LogController do
  render_views

  let(:person) { people(:ul_a_1) }

  before { sign_in(people(:admin)) }

  def changes_html = Nokogiri::HTML(response.body).css(".log-infos").to_html

  it "renders the sleeve length and the order by their form labels" do
    with_versioning do
      person.update!(uniform_long_sleeve: true, uniform_order: true)
      person.update!(uniform_long_sleeve: false, uniform_order: false)
    end

    get(:index, params: {group_id: person.primary_group_id, id: person.id})

    expect(response).to be_successful
    expect(changes_html).to include("Kluft Ärmellänge", "true [Langarm]", "false [Kurzarm]")
    expect(changes_html).to include("Kluft bestellen", "<i>true</i>", "<i>false</i>")
    expect(changes_html).not_to include("[Ja]", "[Nein]")
  end

  it "writes the other answers of the page as stored, a label in brackets where it differs" do
    with_versioning do
      person.update!(headgear: "beanie", diet: "vegan", travel_document_issue_date: Date.new(2020, 5, 4),
        nationality: "deutsch", visa_needed: "no")
    end

    get(:index, params: {group_id: person.primary_group_id, id: person.id})

    expect(changes_html).to include("beanie [Beanie]", "vegan [Vegan]", "2020-05-04 [04.05.2020]",
      "<i>deutsch</i>", "Visum benötigt wurde auf <i>no</i> gesetzt.")
  end
end
