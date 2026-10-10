# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The person log writes a language level of the Zusatzdaten by its German
# label, not as stored, through
# Wsjrdp2027::PaperTrail::VersionDecorator#attribute_change.
describe Person::LogController do
  render_views

  let(:person) { people(:yp_a_1) }

  before { sign_in(people(:admin)) }

  def changes_html = Nokogiri::HTML(response.body).css(".log-infos").to_html

  it "renders the levels by their labels" do
    with_versioning do
      person.update!(english_reading: "none")
      person.update!(english_reading: "native", french_listening: "conversational")
    end

    get(:index, params: {group_id: person.primary_group_id, id: person.id})

    expect(response).to be_successful
    expect(changes_html).to include("Englisch: Lesen", "Keine", "Muttersprache")
    expect(changes_html).to include("Französisch: Hörverstehen", "Konversationssicher")
    expect(changes_html).not_to include("native", "conversational")
  end
end
