# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The log entries of the wagon (Wsjrdp::LogEvents) in the person log, through
# Wsjrdp2027::PaperTrail::VersionDecorator#changes.
describe Person::LogController do
  render_views

  let(:person) { people(:yp_a_1) }

  before { sign_in(people(:admin)) }

  def entry(event, data = {}, item: person, object_changes: nil)
    PaperTrail::Version.create!(item: item, main: person, event: event, wsjrdp_data: data,
      object_changes: object_changes)
  end

  def change_lines
    get(:index, params: {group_id: person.primary_group_id, id: person.id})
    expect(response).to be_successful
    Nokogiri::HTML(response.body).css(".log-infos > div").map { |line| line.inner_html.squish }
  end

  it "shows a tag entry from wsjrdp_data" do
    entry("wsjrdp_add_tag", {"tag_name" => "Bus 3"}, object_changes: YAML.dump({"tag" => [nil, "other"]}))

    expect(change_lines).to eq(["Tag <i>Bus 3</i> hinzugefügt"])
  end

  it "shows an old tag entry from object_changes" do
    entry("wsjrdp_remove_tag", object_changes: YAML.dump({"tag" => ["Bus 2", nil]}))

    expect(change_lines).to eq(["Tag <i>Bus 2</i> entfernt"])
  end

  it "shows a note on one line, its category by label, its message escaped" do
    entry("wsjrdp_note", {"category" => "pre_notification", "message" => "Einzug\nam <b>5.11.</b>",
                          "collection_date" => "2026-11-05"})

    expect(change_lines).to eq(["<i>Vorabankündigung Lastschrift</i>: Einzug am &lt;b&gt;5.11.&lt;/b&gt;"])
  end

  it "shows an unknown category as stored and a missing message as –" do
    entry("wsjrdp_note", {"category" => "<new>"})

    expect(change_lines).to eq(["<i>&lt;new&gt;</i>: –"])
  end

  it "shows an entry whose item is not its main" do
    entry("wsjrdp_note", {"category" => "pre_notification", "message" => "an der Gruppe"},
      item: groups(:unit_a))

    expect(change_lines).to eq(["<i>Vorabankündigung Lastschrift</i>: an der Gruppe"])
  end

  it "shows an unknown event with its data" do
    entry("wsjrdp_unknown", {"a" => "<x>", "b" => {"c" => 1}})

    expect(change_lines).to eq(["Eintrag <i>wsjrdp_unknown</i><br>a: &lt;x&gt;<br>b: {\"c\":1}"])
  end
end
