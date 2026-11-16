# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The person's deregistration_* accessors, which work on the person's current
# deregistration row (WsjrdpDeregistration): its columns, form_snapshot and
# additional_info["refund_receipt"]. A person never deregistered has no row,
# and a value that is the default builds none.
describe "Person deregistration record" do
  let(:person) { people(:yp_a_1) }

  def row = person.reload.deregistration

  describe "with nothing stored" do
    it "has no row at all" do
      expect(person.deregistration).to be_nil
      expect(WsjrdpDeregistration.where(person_id: person.id)).to be_empty
    end

    it "reads the kind as a withdrawal" do
      expect(person.deregistration_kind).to be_nil
      expect(person.deregistration_kind_or_default).to eq("withdrawal")
      expect(person).not_to be_deregistration_termination
    end

    it "reads both flags as shown and the text as nothing" do
      expect(person.deregistration_form_show_contractual_compensation).to be(true)
      expect(person).to be_deregistration_form_show_contractual_compensation
      expect(person.deregistration_refund_receipt_show_default_explanation).to be_nil
      expect(person).to be_deregistration_refund_receipt_show_default_explanation
      expect(person.deregistration_refund_receipt_text).to be_nil
    end

    it "builds no row for the defaults a form sends" do
      person.update!(deregistration_kind: "withdrawal", deregistration_form_show_contractual_compensation: nil,
        deregistration_issue: "", deregistration_refund_receipt_text: "  ")

      expect(row).to be_nil
    end
  end

  describe "the first value" do
    it "makes row 1, recorded, and writes the create event" do
      person.update!(deregistration_issue: "HELP-1")

      expect(row).to have_attributes(number: 1, status: "recorded", issue: "HELP-1")
      expect(row.events.map(&:event)).to eq(["create"])
    end
  end

  describe "#deregistration_reply_due_date" do
    it "keeps the day in its column" do
      person.update!(deregistration_reply_due_date: Date.new(2026, 10, 1))

      expect(row.reply_due_date).to eq(Date.new(2026, 10, 1))
      expect(person.reload.deregistration_reply_due_date).to eq(Date.new(2026, 10, 1))
    end

    it "clears the column again" do
      person.update!(deregistration_reply_due_date: Date.new(2026, 10, 1))

      person.update!(deregistration_reply_due_date: "")

      expect(row.reply_due_date).to be_nil
    end
  end

  # A cancelled registration never became a contract, so the T&R ask for
  # nothing -- and what the person paid comes back unless an amount is entered.
  describe "a cancelled registration" do
    it "carries no compensation under the T&R" do
      expect(person.deregistration_contractual_compensation_cents).to be > 0

      person.update!(deregistration_kind: "cancellation")

      expect(person.reload.deregistration_contractual_compensation_cents).to eq(0)
      expect(person.deregistration_refund_cents).to eq(person.amount_paid_cents)
      expect(person.deregistration_open_cents).to eq(0)
    end

    it "keeps a compensation that was entered, in euros on the row" do
      person.update!(deregistration_kind: "cancellation", deregistration_actual_compensation_cents: 5_050)

      expect(row.actual_compensation).to eq(BigDecimal("50.5"))
      expect(person.reload.deregistration_actual_compensation_cents).to eq(5_050)
      expect(person.deregistration_contractual_compensation_cents).to eq(0)
      expect(person.deregistration_open_cents).to eq([5_050 - person.amount_paid_cents, 0].max)
    end
  end

  describe "#deregistration_kind" do
    it "reads a termination as one" do
      person.update!(deregistration_kind: "termination")

      expect(row.kind).to eq("termination")
      expect(person.deregistration_kind).to eq("termination")
      expect(person).to be_deregistration_termination
    end

    it "rejects a value outside the kinds" do
      person.deregistration_kind = "foo"

      expect(person).not_to be_valid
      expect(person.errors[:deregistration_kind]).to be_present
    end

    it "goes back to the withdrawal when the value is blanked" do
      person.update!(deregistration_kind: "termination")

      person.update!(deregistration_kind: "")

      expect(row.kind).to eq("withdrawal")
      expect(person.deregistration_kind_or_default).to eq("withdrawal")
    end
  end

  describe "the two document flags" do
    it "keeps an explicit off of the form's flag in its column, and on again" do
      person.update!(deregistration_form_show_contractual_compensation: false)
      expect(row.show_contractual_compensation).to be(false)
      expect(person).not_to be_deregistration_form_show_contractual_compensation

      person.update!(deregistration_form_show_contractual_compensation: nil)
      expect(row.show_contractual_compensation).to be(true)
    end

    it "keeps an explicit off of the receipt's flag with the receipt" do
      person.update!(deregistration_refund_receipt_show_default_explanation: false)
      expect(row.receipt).to eq("show_default_explanation" => false)
      expect(person.reload).not_to be_deregistration_refund_receipt_show_default_explanation

      person.update!(deregistration_refund_receipt_show_default_explanation: nil)
      expect(row.additional_info).to eq({})
    end
  end

  describe "#deregistration_refund_receipt_text" do
    it "keeps the text with its line structure" do
      person.update!(deregistration_refund_receipt_text: "Hallo Team,\n\nbitte zurück:\nsoweit klar")

      expect(person.reload.deregistration_refund_receipt_text)
        .to eq("Hallo Team,\n\nbitte zurück:\nsoweit klar")
    end

    it "strips what surrounds the text" do
      person.update!(deregistration_refund_receipt_text: "  Hallo Team\n\n")

      expect(row.receipt).to eq("text" => "Hallo Team")
    end

    it "drops the value for whitespace alone" do
      person.update!(deregistration_refund_receipt_text: "Hallo Team")

      person.update!(deregistration_refund_receipt_text: "   \n ")

      expect(row.receipt).to eq({})
      expect(person.reload.deregistration_refund_receipt_text).to be_nil
    end
  end

  # A value a writer cannot read survives valid? as the field's error and
  # leaves the stored value alone.
  describe "values that cannot be read" do
    it "names a date that is no date and an amount that is no number" do
      person.update!(deregistration_effective_date: Date.new(2026, 10, 31))

      person.deregistration_effective_date = "kein Datum"
      person.deregistration_actual_compensation_cents = "zwölf"

      expect(person).not_to be_valid
      expect(person.errors.attribute_names).to include(:deregistration_effective_date,
        :deregistration_actual_compensation_cents)
      expect(person.deregistration_effective_date).to eq(Date.new(2026, 10, 31))

      person.deregistration_effective_date = "2026-11-30"
      person.deregistration_actual_compensation_cents = "1200"
      expect(person).to be_valid
    end

    # Wsjrdp::DateInput: ISO and German spellings, no fragments.
    it "reads German dates, short years included, and refuses fragments" do
      person.deregistration_effective_date = "1.2.27"
      expect(person.deregistration_effective_date).to eq(Date.new(2027, 2, 1))

      person.deregistration_effective_date = "3"
      expect(person).not_to be_valid
      expect(person.deregistration_effective_date).to eq(Date.new(2027, 2, 1))
    end

    it "keeps what was typed for the date field, until a readable value follows" do
      person.deregistration_effective_date = "31.02.2026"
      expect(person.timeliness_cache_attribute(:deregistration_effective_date)).to eq("31.02.2026")

      person.deregistration_effective_date = "28.02.2026"
      expect(person.timeliness_cache_attribute(:deregistration_effective_date)).to be_nil
    end

    it "names an amount in euros that is no number" do
      person.deregistration_actual_compensation_eur = "12,50 €"

      expect(person).not_to be_valid
      expect(person.errors.attribute_names).to include(:deregistration_actual_compensation_eur)

      # BigDecimal reads these, but they have no cents.
      %w[NaN Infinity].each do |text|
        person.deregistration_actual_compensation_eur = text
        expect(person).not_to be_valid, text
      end

      person.deregistration_actual_compensation_eur = "12.50"
      expect(person).to be_valid
      expect(person.deregistration_actual_compensation_cents).to eq(1250)
    end
  end

  describe "the stored shape" do
    it "puts the columns, the made form's data and the receipt each in their place" do
      person.update!(deregistration_issue: "Ticket 1", deregistration_effective_date: Date.new(2026, 10, 31),
        deregistration_kind: "termination", deregistration_form_created_date: Date.new(2026, 10, 2),
        deregistration_refund_iban: "DE02120300000000202051", deregistration_refund_receipt_text: "Hallo Team")

      expect(row).to have_attributes(issue: "Ticket 1", effective_date: Date.new(2026, 10, 31), kind: "termination")
      expect(row.form_snapshot).to eq("created_date" => "2026-10-02", "refund_iban" => "DE02120300000000202051")
      expect(row.receipt).to eq("text" => "Hallo Team")
      expect(person.reload.additional_info.keys.grep(/deregistration/)).to be_empty
    end
  end

  describe "a form that went out" do
    before do
      person.update!(deregistration_issue: "HELP-1")
      person.deregistration.update!(form_sent_at: Time.current, status: "form_sent")
    end

    it "keeps what the form says" do
      person.reload.deregistration_issue = "HELP-2"

      expect(person.save).to be(false)
      expect(row.issue).to eq("HELP-1")
    end

    it "takes changes in a new version, the old one superseded" do
      replacement = person.reload.deregistration.new_version!

      expect(replacement).to have_attributes(number: 2, status: "recorded", issue: "HELP-1",
        replaces_id: WsjrdpDeregistration.find_by!(person_id: person.id, number: 1).id)
      expect(WsjrdpDeregistration.find_by!(person_id: person.id, number: 1)).to have_attributes(
        status: "superseded", closed_at: be_present
      )
      person.reload.update!(deregistration_issue: "HELP-2")
      expect(row).to have_attributes(number: 2, issue: "HELP-2")
    end
  end

  describe "#total_fee_reduction_text" do
    it "is nothing while the fee is the regular one" do
      expect(person.total_fee_reduction_text).to be_nil
      expect(person.total_fee_label).to eq("Beitrag")
    end

    it "says how much was taken off where nobody wrote a reason" do
      person.update!(wsjrdp_total_fee_reduction: 500)

      expect(person.total_fee_reduction_text).to eq("reduziert um 500€")
      expect(person.total_fee_label).to eq("Beitrag (reduziert um 500€)")
    end

    it "leads with what the reduction was granted for" do
      person.update!(wsjrdp_total_fee_reduction: 500,
        wsjrdp_total_fee_reduction_hint: "rdp Delegate")

      expect(person.total_fee_reduction_text).to eq("rdp Delegate: reduziert um 500€")
      expect(person.total_fee_label).to eq("Beitrag (rdp Delegate: reduziert um 500€)")
    end

    # The label is what a finance view prints, so it keeps its markup: the
    # separators it is given, and html_safe throughout.
    it "is the plain text the label is built from" do
      person.update!(wsjrdp_total_fee_reduction: 500,
        wsjrdp_total_fee_reduction_hint: "rdp Delegate")

      expect(person.total_fee_reduction_text).not_to be_html_safe
      expect(person.total_fee_label).to be_html_safe
      expect(person.total_fee_label(hint_sep: "_", space: "+"))
        .to eq("Beitrag_(rdp+Delegate:+reduziert+um+500€)")
    end
  end
end
