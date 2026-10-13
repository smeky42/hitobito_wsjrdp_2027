# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The person log writes the uniform's sleeve length and order as the forms
# say them (Langarm/Kurzarm, Ja/Nein), through
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
    expect(changes_html).to include("Kluft Ärmellänge", "Langarm", "Kurzarm")
    expect(changes_html).to include("Kluft bestellen", "Ja", "Nein")
    expect(changes_html).not_to include("<i>ja</i>", "<i>nein</i>")
  end
end
