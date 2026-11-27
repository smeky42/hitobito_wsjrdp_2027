# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp2027::GroupPersonPaths do
  include Rails.application.routes.url_helpers

  let(:ul) { people(:ul_a_1) }
  let(:other) { groups(:ist_a) }

  it "answers the short path and URL for the primary group, as a record or an id" do
    aggregate_failures do
      expect(group_person_path(ul.primary_group, ul)).to eq("/people/#{ul.id}")
      expect(group_person_path(ul.primary_group_id, ul)).to eq("/people/#{ul.id}")
      expect(group_person_path(ul.primary_group, ul, format: :html)).to eq("/people/#{ul.id}")
      expect(group_person_url(ul.primary_group, ul, host: "example.com")).to eq("http://example.com/people/#{ul.id}")
    end
  end

  it "keeps the group's URL for another group, a person given by id, a format or other options" do
    aggregate_failures do
      expect(group_person_path(other, ul)).to eq("/groups/#{other.id}/people/#{ul.id}")
      expect(group_person_path(ul.primary_group, ul.id)).to eq("/groups/#{ul.primary_group_id}/people/#{ul.id}")
      expect(group_person_path(ul.primary_group, ul, format: :pdf))
        .to eq("/groups/#{ul.primary_group_id}/people/#{ul.id}.pdf")
      expect(group_person_path(ul.primary_group, ul, returning: true))
        .to eq("/groups/#{ul.primary_group_id}/people/#{ul.id}?returning=true")
      expect(group_person_path(ul.primary_group, ul, format: nil)).to eq("/groups/#{ul.primary_group_id}/people/#{ul.id}")
    end
  end

  it "keeps the group's URL for a person without a primary group" do
    ul.primary_group_id = nil

    expect(group_person_path(other, ul)).to eq("/groups/#{other.id}/people/#{ul.id}")
  end
end
