# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Fin::DebitReturnNoticesHelper do
  let(:person) { people(:yp_a_1) }
  let(:entry) do
    AccountingEntry.create!(subject: person, author: people(:admin), amount_cents: -10_300, amount_currency: "EUR",
      return_reason: "MS03", description: "Rücklastschrift", value_date: Date.new(2026, 11, 10))
  end

  def note!(message, category: "debit_return", data: {})
    Wsjrdp::LogEntry.note!(entry, main: person, category: category, message: message, data: data, whodunnit: nil)
  end

  it "is empty without a mail" do
    expect(helper.fin_debit_return_notices(entry)).to eq([])
  end

  it "joins a stored mail with the note it names, adds a note nobody names, and leaves other categories out" do
    named = note!("Per E-Mail informiert.")
    unnamed = note!("Zweite Mail.", data: {"email_subject" => "Erinnerung", "sent_at" => "2026-11-13T09:30:00+00:00"})
    note!("Vorab informiert.", category: "pre_notification")
    entry.update!(additional_info: {"debit_return_notifications" => [{
      "sent_at" => "2026-11-12T09:30:00+00:00", "email_to" => ["kim@example.org"], "email_cc" => [""],
      "email_subject" => "WSJ27 Einzug 2026-11 Retoure", "debit_return_issue" => "FIN-354",
      "log_version_id" => named.id
    }]})

    notices = helper.fin_debit_return_notices(entry)

    expect(notices.map { |n| [n.subject, n.to, n.cc, n.issue, n.log_note] }).to eq([
      ["WSJ27 Einzug 2026-11 Retoure", ["kim@example.org"], [], "FIN-354", named],
      ["Erinnerung", [], [], nil, unnamed]
    ])
    expect(notices.first.sent_at).to eq(Time.zone.parse("2026-11-12T09:30:00+00:00"))
  end
end
