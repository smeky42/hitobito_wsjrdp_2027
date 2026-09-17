# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# What the finance team pays a deregistration back from. Two fields have a hard
# length -- the booking text Moss shows (60) and the remittance information of
# the transfer (140 by SEPA, of which Moss leaves us 103) -- and both keep the
# role, the registration id and the ticket whatever happens to the name.
describe Wsjrdp2027::RefundReceipt do
  let(:person) { people(:yp_a_1) }
  let(:receipt) { described_class.new(person.reload) }

  before do
    AccountingEntry.create!(subject: person, author: people(:admin), amount_cents: 40_000,
      amount_currency: "EUR", description: "Teilnahmebeitrag",
      value_date: Date.new(2026, 2, 1), booking_date: Date.new(2026, 2, 1))
    person.update!(deregistration_issue: "HELP-1",
      deregistration_requested_date: Date.new(2026, 9, 30),
      deregistration_effective_date: Date.new(2026, 10, 31),
      deregistration_actual_compensation_cents: 0,
      sepa_name: "Kim Alex Muster-Beispiel",
      sepa_iban: "DE02120300000000202051")
  end

  describe "#booking_text" do
    it "names the kind, the role, the id, the person and the ticket" do
      expect(receipt.booking_text).to start_with("Abm. YP #{person.id} ")
      expect(receipt.booking_text).to end_with(" HELP-1")
      expect(receipt.booking_text).to include(person.full_name)
      expect(receipt.booking_text.length).to be <= described_class::BOOKING_TEXT_MAX
    end

    it "gives up the name before the ticket when the room runs out" do
      person.update!(last_name: "M" * 60)

      expect(receipt.booking_text).to eq("Abm. YP #{person.id} Y. M. HELP-1")
      expect(receipt.booking_text.length).to be <= described_class::BOOKING_TEXT_MAX
    end

    it "keeps the name as it was typed" do
      person.update!(first_name: "Jörg", last_name: "Müller")

      expect(receipt.booking_text).to include("Jörg Müller")
    end
  end

  describe "#purpose" do
    it "carries the role, the id, the name and the wording" do
      expect(receipt.purpose)
        .to eq("YP #{person.id} #{person.full_name} / WSJ27 Rueckzahlung nach Abmeldung HELP-1")
    end

    it "stays inside the SEPA character set" do
      person.update!(first_name: "Jörg", last_name: "Müller-Łódź")

      expect(receipt.purpose).to include("Joerg Mueller-Lodz")
      expect(receipt.purpose).to match(/\A[A-Za-z0-9 \/\-?:().,'+]*\z/)
    end

    it "shortens the name until the transliterated line fits" do
      person.update!(first_name: "Jörg Übermäßig", last_name: "Ö" * 70)

      expect(receipt.purpose.length).to be <= described_class::PURPOSE_MAX
      expect(receipt.purpose).to start_with("YP #{person.id} J. Oe. /")
      expect(receipt.purpose).to end_with("/ WSJ27 Rueckzahlung nach Abmeldung HELP-1")
    end

    # The mandatory parts never give way: with a ticket that long there is no
    # room left for a name at all.
    it "drops the name when the fixed parts fill the line" do
      fixed = "YP #{person.id} / WSJ27 Rueckzahlung nach Abmeldung ".length
      ticket = "H" * (described_class::PURPOSE_MAX - fixed)
      person.update!(deregistration_issue: ticket)

      expect(receipt.purpose)
        .to eq("YP #{person.id} / WSJ27 Rueckzahlung nach Abmeldung #{ticket}")
      expect(receipt.purpose.length).to eq(described_class::PURPOSE_MAX)
    end

    it "leaves 103 characters of the 140 SEPA allows, for the uuid Moss appends" do
      expect(described_class::PURPOSE_MAX).to eq(103)
    end
  end

  describe "a termination" do
    before { person.update!(deregistration_kind: "termination") }

    it "is abbreviated and worded as one" do
      expect(receipt.booking_text).to start_with("Kuend. YP #{person.id} ")
      expect(receipt.purpose).to include("/ WSJ27 Rueckzahlung nach Kuendigung HELP-1")
    end
  end

  describe "the values the page shows" do
    it "formats the refund, the dates and the account" do
      expect(receipt.amount_cents).to eq(40_000)
      expect(receipt.amount_text).to eq("400,00 €")
      expect(receipt.requested_date_text).to eq("30.09.2026")
      expect(receipt.effective_date_text).to eq("31.10.2026")
      expect(receipt.account_holder).to eq("Kim Alex Muster-Beispiel")
      expect(receipt.iban).to eq("DE02120300000000202051")
      expect(receipt.team_unit).to eq("YP")
    end

    it "names the unit code where the group has one" do
      groups(:unit_a).update!(additional_info: {"group_code" => "A1"})

      expect(receipt.team_unit).to eq("A1")
    end

    it "offers a refund of zero as well" do
      person.update!(deregistration_actual_compensation_cents: 40_000)

      expect(receipt.amount_cents).to eq(0)
      expect(receipt.amount_text).to eq("0,00 €")
    end

    it "leaves a missing date empty" do
      person.update!(deregistration_requested_date: nil, deregistration_effective_date: nil)

      expect(receipt.requested_date_text).to eq("")
      expect(receipt.effective_date_text).to eq("")
    end

    it "hands every input to typst as a String" do
      expect(receipt.to_sys_inputs.values).to all(be_a(String))
      expect(receipt.to_sys_inputs[:person_id]).to eq(person.id.to_s)
    end

    # The same creditor the page's creditor section states.
    it "names the creditor the refund is paid to" do
      expect(receipt.creditor_name).to eq("TN #{person.id}")
      expect(receipt.to_sys_inputs[:creditor_name]).to eq("TN #{person.id}")
    end
  end

  describe "#file_name" do
    it "names the person and what the document is" do
      expect(receipt.file_name)
        .to eq("WSJ27 Abmeldung YP #{person.id} YP1 UnitA Rückzahlung.pdf")
    end

    it "says Kündigung where the contingent ended it" do
      person.update!(deregistration_kind: "termination")

      expect(receipt.file_name)
        .to eq("WSJ27 Kündigung YP #{person.id} YP1 UnitA Rückzahlung.pdf")
    end

    # The name reads as the document is called; only what a file system would
    # choke on gives way.
    it "keeps the umlauts and replaces what a file name must not carry" do
      person.update!(first_name: "Jörg", last_name: "Müller/Groß")

      expect(receipt.file_name)
        .to eq("WSJ27 Abmeldung YP #{person.id} Jörg Müller_Groß Rückzahlung.pdf")
    end

    it "replaces the rest of the forbidden characters too" do
      person.update!(last_name: "A|B:C*D?E\"F<G>H")

      expect(receipt.file_name).to include("A_B_C_D_E_F_G_H")
    end
  end

  describe "the letter around the table" do
    it "names the role, the id and the short name in the title" do
      expect(receipt.title).to eq("Überweisung einer Rückzahlung an YP #{person.id} YP1 UnitA")
    end

    it "carries no text of its own until one is stored" do
      expect(receipt.greeting).to eq("")
    end

    it "takes the stored text instead, line structure and all" do
      person.update!(deregistration_refund_receipt_text: "Hallo Team,\n\nbitte zurück:\nsoweit klar")

      expect(receipt.greeting).to eq("Hallo Team,\n\nbitte zurück:\nsoweit klar")
    end

    it "says when it was made, and by whom where that is known" do
      admin = people(:admin)

      expect(described_class.new(person, generated_by: admin).generated_by_name)
        .to eq(admin.full_name)
      expect(receipt.generated_by_name).to eq("")
      expect(receipt.generated_on_text).to eq(I18n.l(Date.current))
    end

    it "hands all of it to typst" do
      inputs = described_class.new(person.reload, generated_by: people(:admin)).to_sys_inputs

      expect(inputs[:title]).to eq("Überweisung einer Rückzahlung an YP #{person.id} YP1 UnitA")
      expect(inputs[:greeting]).to eq("")
      expect(inputs[:generated_on]).to eq(I18n.l(Date.current))
      expect(inputs[:generated_by]).to eq(people(:admin).full_name)
    end
  end

  # The paragraph the template composes is given its parts, not a finished
  # sentence: what happened, for which role, and the four amounts.
  describe "the explanation the template writes" do
    it "is shown until it is switched off" do
      expect(receipt.show_explanation?).to be(true)
      expect(receipt.to_sys_inputs[:show_explanation]).to eq("true")

      person.update!(deregistration_refund_receipt_show_default_explanation: false)

      expect(described_class.new(person.reload).show_explanation?).to be(false)
      expect(described_class.new(person.reload).to_sys_inputs[:show_explanation]).to eq("false")
    end

    it "says which of the two ended the participation" do
      expect(receipt.kind).to eq("withdrawal")

      person.update!(deregistration_kind: "termination")

      expect(described_class.new(person.reload).kind).to eq("termination")
    end

    # The same words the contract uses, so the two documents say one thing.
    it "names the role the way the contract does" do
      expect(receipt.role_name).to eq("Youth Participant in einer Unit")
      expect(described_class.new(people(:ul_a_1)).role_name).to eq("Unit Leader einer Unit")
      expect(described_class.new(people(:ist_a_1)).role_name)
        .to eq("International Service Team Mitglied")
    end

    it "carries the fee, what was paid and what is kept" do
      expect(receipt.total_fee_text).to match(/\A[\d.]+,\d\d €\z/)
      expect(receipt.amount_paid_text).to eq("400,00 €")
      expect(receipt.compensation_text).to eq("0,00 €")
      expect(receipt.to_sys_inputs[:refund]).to eq(receipt.amount_text)
      expect(receipt.to_sys_inputs[:role_name]).to eq("Youth Participant in einer Unit")
    end

    # The sentence states the fee the way the contract states it: the euro
    # amount without cents, with the reason behind it where the fee was reduced
    # for one. The spaces are the non-breaking ones Person#total_fee_eur_text
    # sets.
    it "states the fee the way the contract does" do
      expect(receipt.to_sys_inputs[:total_fee]).to eq(person.total_fee_eur_text)
      expect(receipt.to_sys_inputs[:total_fee]).to match(/\A[\d.]+[[:space:]]€\z/)

      person.update!(wsjrdp_total_fee_reduction: 500, wsjrdp_total_fee_reduction_hint: "rdp Delegate")

      expect(described_class.new(person.reload).to_sys_inputs[:total_fee])
        .to match(/\A[\d.]+[[:space:]]€[[:space:]]\(rdp Delegate\)\z/)
    end
  end

  # What the fee is called: the reduction names itself, in the preview row and
  # nowhere else -- the sentence has the contract's own wording for it.
  describe "#total_fee_label" do
    it "is the plain word while the fee is the regular one" do
      expect(receipt.fee_reason).to be_nil
      expect(receipt.total_fee_label).to eq("Beitrag")
      expect(receipt.total_fee_label).not_to be_html_safe
    end

    it "names what the reduction was granted for" do
      person.update!(wsjrdp_total_fee_reduction: 500, wsjrdp_total_fee_reduction_hint: "rdp Delegate")
      receipt = described_class.new(person.reload)

      expect(receipt.fee_reason).to eq("rdp Delegate")
      expect(receipt.total_fee_label).to eq("Beitrag (rdp Delegate)")
    end

    it "falls back to how much was taken off" do
      person.update!(wsjrdp_total_fee_reduction: 500)
      receipt = described_class.new(person.reload)

      expect(receipt.fee_reason).to eq("reduziert um 500€")
      expect(receipt.total_fee_label).to eq("Beitrag (reduziert um 500€)")
    end

    # The same rule the page's Entschädigung row follows: what was agreed on,
    # or the bracket of section 7.2 T&R while nothing was.
    it "falls back to the contractual compensation" do
      person.update!(deregistration_actual_compensation_cents: nil)
      receipt = described_class.new(person.reload)

      expect(person.deregistration_actual_compensation_cents).to be_nil
      expect(receipt.compensation_cents)
        .to eq(person.deregistration_contractual_compensation_cents)
      expect(receipt.compensation_cents).to be > 0
    end
  end

  describe "#to_pdf" do
    it "compiles the template" do
      pdf = receipt.to_pdf

      expect(pdf).to start_with("%PDF")
      expect(pdf.bytesize).to be > 1_000
    end

    it "compiles a stored text that looks like typst markup, as text" do
      person.update!(deregistration_refund_receipt_text: "Hallo,\n\n#emph[x] und *y* und $z$")

      expect(described_class.new(person.reload, generated_by: people(:admin)).to_pdf)
        .to start_with("%PDF")
    end

    it "compiles without the explanation paragraph" do
      person.update!(deregistration_refund_receipt_show_default_explanation: false)

      expect(described_class.new(person.reload).to_pdf).to start_with("%PDF")
    end

    # Without a request date the paragraph leaves a line to fill in by hand.
    it "compiles while the request date is still open" do
      person.update!(deregistration_requested_date: nil)

      expect(described_class.new(person.reload).to_pdf).to start_with("%PDF")
    end
  end
end
