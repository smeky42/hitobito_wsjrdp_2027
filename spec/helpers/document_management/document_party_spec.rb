# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The subject and the author of a document.
describe DocumentManagement::DocumentsHelper, type: :helper do
  let(:person) { people(:cmt_leader) }

  it "links a person like any person" do
    html = Capybara.string(helper.document_party("Person", person.id, {person.id => person}).to_s)

    expect(html).to have_link(person.to_s, href: "/people/#{person.id}")
  end

  it "marks a person that is gone, and names any other party by type and id" do
    expect(Capybara.string(helper.document_party("Person", 7, {}).to_s).text).to start_with("Person 7 (")
    expect(helper.document_party("Group", 7, {})).to eq("Group 7")
  end
end
