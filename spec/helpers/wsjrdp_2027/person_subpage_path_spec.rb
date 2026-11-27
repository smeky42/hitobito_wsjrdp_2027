# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The tabs of the person's print, upload, unit, history, log and security
# pages: the short URL in the primary group or without one, the group's URL
# in any other group.
describe Wsjrdp2027::PeopleHelper do
  let(:ul) { people(:ul_a_1) }

  it "links the short URL in the primary group and without a group, the group's URL elsewhere" do
    other = groups(:ist_a)

    expect([helper.print_tab_path(ul.primary_group, ul), helper.log_tab_path(nil, ul),
      helper.security_tools_tab_path(other, ul)])
      .to eq(["/people/#{ul.id}/print", "/people/#{ul.id}/log",
        "/groups/#{other.id}/people/#{ul.id}/security_tools"])
  end

  it "links the short URL for a person without a primary group" do
    ul.primary_group_id = nil

    expect(helper.unit_tab_path(groups(:ist_a), ul)).to eq("/people/#{ul.id}/unit")
  end
end
