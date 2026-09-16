# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The person log renders a change of additional_info["finance_group_ids"]
# (doc/roles.md -> "Finance on a group's page") per group, through
# Wsjrdp2027::PaperTrail::VersionDecorator#attribute_change. The log page is
# used instead of a decorator spec because the core's :draper_with_helpers hook
# reads a core fixture this wagon does not have.
describe Person::LogController do
  render_views

  let(:person) { people(:cmt_leader) }
  let(:unit_a) { groups(:unit_a) }
  let(:unit_b) { groups(:unit_b) }

  before { sign_in(people(:admin)) }

  def log = get(:index, params: {group_id: person.primary_group_id, id: person.id})

  # A version row in the shape the scripts in wsjrdp_scripts write.
  def version(changes)
    PaperTrail::Version.create!(
      main: person,
      item: person,
      event: "update",
      whodunnit: people(:admin).id.to_s,
      object_changes: YAML.dump(changes)
    )
  end

  # Only the change lines, so the assertions do not see the surrounding layout.
  def changes_html = Nokogiri::HTML(response.body).css(".log-infos").to_html

  it "renders a change written through the model" do
    with_versioning do
      person.update!(finance_group_ids: {unit_a.id.to_s => "show"})
    end

    log

    expect(response).to be_successful
    expect(changes_html)
      .to include("Finanzzugriff auf Gruppe <i>Unit A</i> wurde auf <i>Anzeigen</i> gesetzt.")
    expect(changes_html).not_to include("=>")
  end

  it "renders one line per group, ordered by group name" do
    version("finance_group_ids" => [
      {unit_a.id.to_s => "show"},
      {unit_a.id.to_s => "show,update", unit_b.id.to_s => "show"}
    ])

    log

    expect(changes_html).to include(
      "Finanzzugriff auf Gruppe <i>Unit A</i> wurde von <i>Anzeigen</i> " \
      "auf <i>Anzeigen, Bearbeiten</i> geändert."
    )
    expect(changes_html)
      .to include("Finanzzugriff auf Gruppe <i>Unit B</i> wurde auf <i>Anzeigen</i> gesetzt.")
    expect(changes_html.index("Gruppe <i>Unit A</i>"))
      .to be < changes_html.index("Gruppe <i>Unit B</i>")
  end

  it "renders the removal of the whole field" do
    version("finance_group_ids" => [{unit_a.id.to_s => "show"}, nil])

    log

    expect(changes_html)
      .to include("Finanzzugriff auf Gruppe <i>Unit A</i> <i>Anzeigen</i> wurde gelöscht.")
  end

  it "renders an unknown token as it is and an unknown group by its id" do
    version("finance_group_ids" => [nil, {"999999999" => "show, <b>audit</b>"}])

    log

    expect(changes_html).to include(
      "Finanzzugriff auf Gruppe <i>#999999999</i> wurde auf " \
      "<i>Anzeigen, &lt;b&gt;audit&lt;/b&gt;</i> gesetzt."
    )
  end

  it "leaves a change of another attribute to the core" do
    version("first_name" => ["Leader", "Chef"])

    log

    expect(changes_html).to include("Vorname wurde von <i>Leader</i> auf <i>Chef</i> geändert.")
  end
end
