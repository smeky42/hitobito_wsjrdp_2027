# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The person log renders a change of additional_info["deregistration_record"]
# (Wsjrdp2027::DeregistrationRecord) per value, through
# Wsjrdp2027::PaperTrail::VersionDecorator#attribute_change, in the words the
# Abmeldung page's flash uses. The log page is used instead of a decorator spec
# because the core's :draper_with_helpers hook reads a core fixture this wagon
# does not have.
describe Person::LogController do
  render_views

  let(:person) { people(:cmt_leader) }
  let(:key) { Wsjrdp2027::DeregistrationRecord::KEY }

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
      person.update!(deregistration_kind: "termination")
    end

    log

    expect(response).to be_successful
    expect(changes_html)
      .to include("Art: Abmeldung (durch die Person) → Kündigung (durch das Kontingent)")
    expect(changes_html).not_to include("=>", key)
  end

  it "renders one line per changed value, in the order the form asks for them" do
    version(key => [
      {"kind" => "withdrawal"},
      {"kind" => "termination", "refund_receipt_text" => "Hallo Team"}
    ])

    log

    expect(changes_html)
      .to include("Art: Abmeldung (durch die Person) → Kündigung (durch das Kontingent)")
    expect(changes_html).to include("Text im Beleg: – → Hallo Team")
    expect(changes_html.index("Art:")).to be < changes_html.index("Text im Beleg:")
  end

  # A stored default that vanished reads exactly like the absence it stood for.
  it "leaves a stored default that vanished out" do
    version(key => [{"kind" => "withdrawal", "form_show_contractual_compensation" => true}, nil])

    log

    expect(response).to be_successful
    expect(changes_html).not_to include("Art:", "Abmelde-Formular")
  end

  it "leaves a value that stayed as it was out" do
    version(key => [
      {"kind" => "termination"},
      {"kind" => "termination", "refund_receipt_show_default_explanation" => false}
    ])

    log

    expect(changes_html).to include("Erklärungsabsatz im Beleg: anzeigen → ausblenden")
    expect(changes_html).not_to include("Art:")
  end

  # The whole sub-object gone means every value back to its default, and the
  # defaults are what the page shows.
  it "renders the removal of the whole sub-object" do
    version(key => [
      {"kind" => "termination", "form_show_contractual_compensation" => false},
      nil
    ])

    log

    expect(changes_html)
      .to include("Art: Kündigung (durch das Kontingent) → Abmeldung (durch die Person)")
    expect(changes_html)
      .to include("Entschädigung nach T&amp;R im Abmelde-Formular: ausblenden → anzeigen")
  end

  # A key the record does not know is none of its business, so it gets no line.
  it "says nothing about a value it does not know" do
    version(key => [nil, {"something_else" => "x"}])

    log

    expect(changes_html).not_to include("something_else", "→")
  end

  it "escapes what was typed into the text" do
    version(key => [nil, {"refund_receipt_text" => "Hallo <b>Team</b>"}])

    log

    expect(changes_html).to include("Text im Beleg: – → Hallo &lt;b&gt;Team&lt;/b&gt;")
  end

  it "leaves a change of another attribute to the core" do
    version("first_name" => ["Leader", "Chef"])

    log

    expect(changes_html).to include("Vorname wurde von <i>Leader</i> auf <i>Chef</i> geändert.")
  end
end
