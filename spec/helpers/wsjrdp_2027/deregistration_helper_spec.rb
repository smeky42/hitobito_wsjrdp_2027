# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# What the Abmeldung page says, line by line.
describe Wsjrdp2027::PeopleHelper do
  let(:person) { people(:yp_a_1) }

  def book_payment(cents)
    AccountingEntry.create!(subject: person, author: people(:admin), amount_cents: cents, amount_currency: "EUR",
      description: "Teilnahmebeitrag", value_date: Date.new(2026, 2, 1), booking_date: Date.new(2026, 2, 1))
  end

  def mail_event(row, info) =
    WsjrdpDeregistrationEvent.create!(deregistration: row, event: "notify", action: "form_sent",
      occurred_at: Time.current, additional_info: info)

  describe "#deregistration_settlement_formula" do
    before { book_payment(10_000) }

    it "takes the compensation from what was paid for a refund" do
      person.update!(deregistration_actual_compensation_cents: 5_000)

      expect(helper.deregistration_settlement_formula(person.reload)).to match(/\A= 100.*\(bezahlt\) − 50.*\(Einbehalt\)\z/)
    end

    it "takes what was paid from the compensation for a claim" do
      person.update!(deregistration_actual_compensation_cents: 50_000)

      expect(helper.deregistration_settlement_formula(person.reload)).to match(/\A= 500.*\(Einbehalt\) − 100.*\(bezahlt\)\z/)
    end
  end

  it "names the stored days of the form only, the request date after the kind" do
    person.update!(deregistration_kind: "termination", deregistration_requested_date: Date.new(2026, 11, 12))

    facts = helper.deregistration_form_facts(Wsjrdp2027::DeregistrationForm.new(person.reload))

    expect(facts).to include("Gekündigt am 12.11.2026")
    expect(facts).not_to include("Abmeldung zum")
  end

  it "marks a mail that carried a form discarded since" do
    person.update!(deregistration_form_created_date: Date.new(2026, 11, 20))
    mail = {"email_sent_at" => "2026-11-15T14:03:12+01:00", "email_to" => ["yp@example.org"]}
    row = person.reload.deregistration
    mail_event(row, mail.merge("form_created_date" => "2026-11-15"))
    mail_event(row, mail.merge("form_created_date" => "2026-11-20"))

    expect(helper.deregistration_form_mailing_lines(person.reload))
      .to eq(["Verschickt am 15.11.2026 – zu einem verworfenen Formular", "Verschickt am 15.11.2026"])
  end

  describe "#deregistration_history_entries" do
    before do
      person.update!(deregistration_effective_date: Date.new(2026, 10, 31))
      person.update!(deregistration_issue: "HELP-1")
    end

    def lines = helper.deregistration_history_entries(person.reload).pluck(:line)

    it "lists the changes newest first, each with what it changed" do
      entries = helper.deregistration_history_entries(person.reload)

      expect(entries.pluck(:line)).to match([a_string_ending_with("Nr. 1 · Angaben geändert"),
        a_string_ending_with("Nr. 1 · Erfasst")])
      expect(entries.first[:details]).to eq(["Ticket Abmeldung: – → HELP-1"])
    end

    it "tells a form sent with its mail in one line" do
      row = person.reload.deregistration
      mail_event(row, {"email_to" => ["a@example.org"]})
      row.update!(form_sent_at: Time.current, status: "form_sent")

      expect(lines.grep(/verschickt/)).to match([a_string_including("Formular per E-Mail verschickt an a@example.org")])
      expect(lines.grep(/Formular verschickt\b/)).to be_empty
    end

    it "keeps a step to form_sent reached without a mail right before it" do
      row = person.reload.deregistration
      mail_event(row, {"email_to" => ["a@example.org"]})
      row.update!(comment: "von Hand")
      row.update!(form_sent_at: Time.current, status: "form_sent")

      expect(lines.grep(/Formular verschickt\b/)).to be_present
    end
  end
end
