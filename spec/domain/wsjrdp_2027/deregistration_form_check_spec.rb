# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Whether the Abmelde-Formular can go out complete (errors) and what is worth a
# second look (warnings), all at once.
describe Wsjrdp2027::DeregistrationFormCheck do
  let(:person) { people(:yp_a_1) }

  before do
    person.update_columns(birthday: Date.new(2010, 6, 1), additional_contact_name_a: "Erika UnitA",
      additional_contact_single: true)
    person.update!(deregistration_effective_date: Date.new(2026, 12, 31), deregistration_issue: "HELP-1",
      deregistration_actual_compensation_cents: 15_000)
  end

  def check(today: Date.new(2026, 11, 15)) = described_class.new(person.reload, today: today)

  def codes(entries) = entries.pluck("code")

  it "finds nothing for a complete form" do
    expect(check.as_json).to eq("errors" => [], "warnings" => [])
  end

  it "lists every gap at once" do
    person.update_columns(birthday: nil)
    person.update!(deregistration_kind: "termination", deregistration_actual_compensation_cents: nil,
      deregistration_effective_date: nil)

    expect(codes(check.errors)).to eq(%w[unavailable_termination unavailable_no_date no_compensation no_birthday])
    expect(check.errors.first["message"]).to start_with("Die Art ist Kündigung")
  end

  it "warns about the ticket, an expired deadline, an earlier mail and a missing guardian" do
    person.update_columns(additional_contact_name_a: nil)
    person.update!(deregistration_issue: nil, deregistration_form_created_date: Date.new(2026, 10, 1),
      deregistration_effective_reply_due_date: Date.new(2026, 10, 15))
    WsjrdpDeregistrationEvent.create!(deregistration: person.reload.deregistration, event: "notify",
      action: "form_sent", occurred_at: Time.zone.local(2026, 10, 2),
      additional_info: {"email_sent_at" => "2026-10-02T10:00:00+02:00", "email_to" => ["yp@example.org"]})

    warnings = check.warnings

    expect(codes(warnings)).to eq(%w[no_issue deadline_over sent_before no_guardian])
    expect(warnings[1]["message"]).to eq("Die Frist des Formulars (15.10.2026) ist abgelaufen.")
    expect(warnings[2]["message"]).to eq("Das Formular wurde schon am 02.10.2026 an yp@example.org verschickt.")
    expect(check.errors).to eq([])
  end
end
