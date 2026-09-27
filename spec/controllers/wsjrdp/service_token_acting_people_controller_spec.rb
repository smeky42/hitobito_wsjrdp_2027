# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The search behind a service token's acting person: every person, a person
# without roles included, by name or by id; for admins only.
describe Wsjrdp::ServiceTokenActingPeopleController do
  let(:admin) { people(:admin).tap { |person| Group::Root::Admin.create!(person: person, group: groups(:root)) } }
  let!(:roleless) { Person.create!(first_name: "Ohnerolle", last_name: "Beispiel") }

  def found(q)
    get :index, params: {q: q}
    JSON.parse(response.body).pluck("id")
  end

  context "for an admin" do
    before { sign_in(admin) }

    it "finds a person without roles by name" do
      expect(found("Ohnerol")).to include(roleless.id)
    end

    it "finds a person by an id of any length" do
      expect(found(roleless.id.to_s)).to eq([roleless.id])
      expect(found(people(:yp_a_1).id.to_s).first).to eq(people(:yp_a_1).id)
    end

    it "finds a person by an id with leading zeros, as the autocomplete sends three characters" do
      id = roleless.id
      ["00#{id}", "000#{id}"].each { |q| expect(found(q).first).to eq(id), q }
    end

    it "does not read 'id 1' or '#01' as an id" do
      id = roleless.id
      ["id #{id}", "#0#{id}"].each { |q| expect(found(q)).not_to include(id), q }
    end

    it "answers in the typeahead format" do
      get :index, params: {q: roleless.id.to_s}
      expect(JSON.parse(response.body).first.keys).to contain_exactly("id", "label")
    end
  end

  it "is refused to someone who is not an admin" do
    sign_in(people(:ul_a_1))
    expect { get :index, params: {q: "Ohnerol"} }.to raise_error(CanCan::AccessDenied)
  end
end
