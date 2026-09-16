# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The group log renders a change of additional_info["cost_center_numbers"] per
# NUMBER, through Wsjrdp2027::PaperTrail::VersionDecorator#attribute_change. The
# log page is used instead of a decorator spec because the core's
# :draper_with_helpers hook reads a core fixture this wagon does not have. All
# numbers and names below are invented.
describe Group::LogController do
  render_views

  let(:unit_a) { groups(:unit_a) }

  let!(:cc_a1) { WsjrdpCostCenter.create!(number: "A1", name: "Kostenstelle A1") }
  let!(:cc_a1_r) { WsjrdpCostCenter.create!(number: "A1-R", name: "Kostenstelle A1-R") }

  before { sign_in(people(:cmt_leader)) }

  def log = get(:index, params: {group_id: unit_a.id})

  # Only the change lines, so the assertions do not see the surrounding layout.
  def changes_html = Nokogiri::HTML(response.body).css(".log-infos").to_html

  it "renders one line per number added" do
    with_versioning { unit_a.update!(cost_center_numbers: ["A1", "A1-R"]) }

    log

    expect(response).to be_successful
    expect(changes_html).to include("Gruppen-Kostenstelle <i>#{cc_a1}</i> hinzugefügt")
    expect(changes_html).to include("Gruppen-Kostenstelle <i>#{cc_a1_r}</i> hinzugefügt")
    # The core would render the stored array with Array#to_s.
    expect(changes_html).not_to include("[&quot;")
  end

  it "renders a line for a number that is gone" do
    unit_a.update!(cost_center_numbers: ["A1", "A1-R"])

    with_versioning { unit_a.update!(cost_center_numbers: ["A1-R"]) }

    log

    expect(changes_html).to include("Gruppen-Kostenstelle <i>#{cc_a1}</i> entfernt")
    expect(changes_html).not_to include("<i>#{cc_a1_r}</i>")
  end

  it "renders a number without a cost center as it is" do
    with_versioning { unit_a.update!(cost_center_numbers: ["Z9"]) }

    log

    expect(changes_html).to include("Gruppen-Kostenstelle <i>Z9</i> hinzugefügt")
  end
end
