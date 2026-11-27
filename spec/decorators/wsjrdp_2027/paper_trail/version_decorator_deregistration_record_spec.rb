# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# A change of additional_info["deregistration_record"] (an older entry, from
# before the deregistration had its table) per value, in the words of the
# Abmeldung page.
describe PaperTrail::VersionDecorator, :draper_with_helpers do
  let(:person) { people(:cmt_leader) }
  let(:key) { "deregistration_record" }

  # A version row in the shape the scripts in wsjrdp_scripts write.
  def changes_of(changes)
    version = PaperTrail::Version.create!(main: person, item: person, event: "update",
      whodunnit: people(:admin).id.to_s, object_changes: YAML.dump(changes))
    described_class.new(version).changes.to_s
  end

  it "renders a change of the deregistration row written through the model, by its number" do
    with_versioning do
      person.update!(deregistration_issue: "HELP-1")
      person.reload.update!(deregistration_kind: "termination", deregistration_refund_receipt_text: "Hallo Team",
        deregistration_actual_compensation_cents: 15_050)
    end
    created, updated = PaperTrail::Version.where(item_type: "WsjrdpDeregistration").reorder(:id)
      .map { |version| described_class.new(version).changes.to_s }

    aggregate_failures do
      expect(created).to include("Abmeldung Nr. 1 angelegt:", "Ticket Abmeldung: – → HELP-1")
      expect(updated).to include("Abmeldung Nr. 1 geändert:",
        "Art: Abmeldung (durch die Person) → Kündigung (durch das Kontingent)", "Text im Beleg: – → Hallo Team")
      expect(updated).to match(/: – → 150,50/)
      expect(created + updated).not_to include("=>", "refund_receipt")
    end
  end

  it "renders one line per changed value, in the order the form asks for them" do
    html = changes_of(key => [{"kind" => "withdrawal"}, {"kind" => "termination", "refund_receipt_text" => "Hallo Team"}])

    expect(html).to include("Art: Abmeldung (durch die Person) → Kündigung (durch das Kontingent)",
      "Text im Beleg: – → Hallo Team")
    expect(html.index("Art:")).to be < html.index("Text im Beleg:")
  end

  it "leaves out a stored default that vanished and a value that stayed" do
    vanished = changes_of(key => [{"kind" => "withdrawal", "form_show_contractual_compensation" => true}, nil])
    stayed = changes_of(key => [{"kind" => "termination"},
      {"kind" => "termination", "refund_receipt_show_default_explanation" => false}])

    expect(vanished).not_to include("Art:", "Abmelde-Formular")
    expect(stayed).to include("Erklärungsabsatz im Beleg: anzeigen → ausblenden")
    expect(stayed).not_to include("Art:")
  end

  it "renders the removal of the whole sub-object as every value back to its default" do
    html = changes_of(key => [{"kind" => "termination", "form_show_contractual_compensation" => false}, nil])

    expect(html).to include("Art: Kündigung (durch das Kontingent) → Abmeldung (durch die Person)",
      "Entschädigung nach T&amp;R im Abmelde-Formular: ausblenden → anzeigen")
  end

  it "says nothing about a value it does not know, nor about the form's mails" do
    mailing = {"email_message_id" => "<1@x>", "email_to" => ["a@example.org"]}
    unknown = changes_of(key => [nil, {"something_else" => "x"}])
    mails = changes_of(key => [{"kind" => "termination"}, {"kind" => "withdrawal", "form_mailings" => [mailing]}])

    expect(unknown).not_to include("something_else", "→")
    expect(mails).to include("Art: Kündigung (durch das Kontingent) → Abmeldung (durch die Person)")
    expect(mails).not_to include("form_mailings", "a@example.org", "Mailings")
  end

  it "escapes what was typed into the text" do
    expect(changes_of(key => [nil, {"refund_receipt_text" => "Hallo <b>Team</b>"}]))
      .to include("Text im Beleg: – → Hallo &lt;b&gt;Team&lt;/b&gt;")
  end

  it "leaves a change of another attribute to the core" do
    expect(changes_of("first_name" => ["Leader", "Chef"]))
      .to include("Vorname wurde von <i>Leader</i> auf <i>Chef</i> geändert.")
  end
end
