# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The person log names an allergy's box with its context, "Allergie Milch"
# rather than "Milch", through
# Wsjrdp2027::PaperTrail::VersionDecorator#attribute_change_args.
describe Person::LogController do
  render_views

  let(:person) { people(:yp_a_1) }

  before { sign_in(people(:admin)) }

  def change_lines = Nokogiri::HTML(response.body).css(".log-infos div").map { |line| line.text.squish }

  it "names an allergy as such" do
    with_versioning { person.update!(allergy_milk_level: "mild") }

    get(:index, params: {group_id: person.primary_group_id, id: person.id})

    expect(response).to be_successful
    expect(change_lines).to include("Allergie Milch wurde auf true gesetzt.",
      "Schwere der Milchallergie wurde auf mild [Milde Reaktion (selbst behandelbar)] gesetzt.")
  end
end
