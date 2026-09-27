# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# A request with a token that has an acting person: authorized by token and
# person together, recorded in PaperTrail as the token's.
describe "Service token with an acting person", type: :request do
  let(:person) { people(:yp_a_1) }
  let(:token) do
    ServiceToken.create!(layer: groups(:root), name: "Skript", people: true,
      permission: "layer_and_below_full", acting_person: acting_person)
  end
  let(:payload) do
    {data: {id: person.id.to_s, type: "people", attributes: {first_name: "Geändert"}}}
  end

  before { PaperTrail.enabled = true }
  after { PaperTrail.enabled = false }

  def update_person
    patch "/api/people/#{person.id}", params: payload.to_json,
      headers: {"Content-Type" => "application/vnd.api+json", "Accept" => "application/vnd.api+json",
                "X-Token" => token.plain_token}
  end

  context "who may change the person" do
    let(:acting_person) { people(:admin) }

    it "changes the person and records the token as the author" do
      update_person

      expect(response).to have_http_status(200)
      expect(person.reload.first_name).to eq("Geändert")
      version = PaperTrail::Version.where(main: person).order(:id).last
      expect(version.whodunnit).to eq(token.id.to_s)
      expect(version.whodunnit_type).to eq(ServiceToken.sti_name)
    end
  end

  context "who may not change the person" do
    let(:acting_person) { people(:yp_a_2) }

    it "is refused although the token alone could" do
      update_person

      expect(response).to have_http_status(403)
      expect(person.reload.first_name).not_to eq("Geändert")
    end
  end
end
