# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The person's deregistration_* accessors, which delegate to
# Wsjrdp2027::DeregistrationRecord: the kind of deregistration and what the two
# documents of the Abmeldung page carry, in one sub-object of additional_info.
# An absent value is the default, so the whole sub-object is gone where nothing
# differs from one.
describe "Person deregistration record" do
  let(:person) { people(:yp_a_1) }
  let(:key) { Wsjrdp2027::DeregistrationRecord::KEY }

  def stored = person.reload.additional_info[key]

  describe "with nothing stored" do
    it "carries no sub-object at all" do
      expect(person.additional_info).not_to have_key(key)
      expect(person.deregistration_record)
        .to be_a(Wsjrdp2027::DeregistrationRecord)
    end

    it "reads the kind as a withdrawal" do
      expect(person.deregistration_kind).to be_nil
      expect(person.deregistration_kind_or_default).to eq("withdrawal")
      expect(person).not_to be_deregistration_termination
    end

    it "reads both flags as shown and the text as nothing" do
      expect(person.deregistration_form_show_contractual_compensation).to be_nil
      expect(person).to be_deregistration_form_show_contractual_compensation
      expect(person.deregistration_refund_receipt_show_default_explanation).to be_nil
      expect(person).to be_deregistration_refund_receipt_show_default_explanation
      expect(person.deregistration_refund_receipt_text).to be_nil
    end
  end

  describe "#deregistration_kind" do
    # The withdrawal is what an absent value stands for, so writing it stores
    # nothing -- the form sends it on every save.
    it "stores nothing for an explicit withdrawal" do
      person.update!(deregistration_kind: "withdrawal")

      expect(person.reload.additional_info).not_to have_key(key)
      expect(person.deregistration_kind).to be_nil
      expect(person.deregistration_kind_or_default).to eq("withdrawal")
      expect(person).not_to be_deregistration_termination
    end

    it "reads a termination as one" do
      person.update!(deregistration_kind: "termination")

      expect(stored).to eq("kind" => "termination")
      expect(person.deregistration_kind).to eq("termination")
      expect(person).to be_deregistration_termination
    end

    it "rejects a value outside the two kinds" do
      person.deregistration_kind = "foo"

      expect(person).not_to be_valid
      expect(person.errors[:deregistration_kind]).to be_present
    end

    it "drops the sub-object when the value is blanked" do
      person.update!(deregistration_kind: "termination")

      person.update!(deregistration_kind: "")

      expect(person.reload.additional_info).not_to have_key(key)
      expect(person.deregistration_kind_or_default).to eq("withdrawal")
    end
  end

  describe "the two document flags" do
    %i[
      deregistration_form_show_contractual_compensation
      deregistration_refund_receipt_show_default_explanation
    ].each do |attr|
      describe "##{attr}" do
        let(:sub_key) { Wsjrdp2027::DeregistrationRecord.sub_key(attr) }

        it "keeps an explicit off" do
          person.update!(attr => false)

          expect(stored).to eq(sub_key => false)
          expect(person.send(attr)).to be(false)
          expect(person.send(:"#{attr}?")).to be(false)
        end

        # On is what an absent value stands for, so writing it stores nothing.
        it "stores nothing for an explicit on" do
          person.update!(attr => false)

          person.update!(attr => true)

          expect(person.reload.additional_info).not_to have_key(key)
          expect(person.send(:"#{attr}?")).to be(true)
        end

        # A null would read the same as nothing stored but leave the store
        # saying something it does not mean.
        it "drops the value on nil instead of writing a null" do
          person.update!(attr => false)

          person.update!(attr => nil)

          expect(person.reload.additional_info).not_to have_key(key)
          expect(person.send(:"#{attr}?")).to be(true)
        end
      end
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

      expect(stored).to eq("refund_receipt_text" => "Hallo Team")
    end

    it "drops the value for whitespace alone" do
      person.update!(deregistration_refund_receipt_text: "Hallo Team")

      person.update!(deregistration_refund_receipt_text: "   \n ")

      expect(person.reload.additional_info).not_to have_key(key)
      expect(person.deregistration_refund_receipt_text).to be_nil
    end
  end

  # Every value sits in the one sub-object, and each writer leaves the others
  # where they are.
  describe "the stored shape" do
    it "gathers every value under the one key" do
      person.update!(deregistration_kind: "termination",
        deregistration_form_show_contractual_compensation: false,
        deregistration_refund_receipt_text: "Hallo Team",
        deregistration_refund_receipt_show_default_explanation: false)

      expect(stored).to eq(
        "kind" => "termination",
        "form_show_contractual_compensation" => false,
        "refund_receipt_text" => "Hallo Team",
        "refund_receipt_show_default_explanation" => false
      )
    end

    it "leaves the flat deregistration fields and the rest of the column alone" do
      person.update!(deregistration_issue: "Ticket 1",
        deregistration_effective_date: Date.new(2026, 10, 31),
        deregistration_kind: "termination")

      info = person.reload.additional_info
      expect(info["deregistration_issue"]).to eq("Ticket 1")
      expect(info["deregistration_effective_date"]).to eq("2026-10-31")
      expect(info[key]).to eq("kind" => "termination")
    end

    it "keeps what another writer wrote" do
      person.update!(deregistration_kind: "termination")

      person.update!(deregistration_refund_receipt_text: "Hallo Team")

      expect(stored).to eq("kind" => "termination", "refund_receipt_text" => "Hallo Team")
    end

    it "drops the key again once everything reads as the default" do
      person.update!(deregistration_kind: "termination",
        deregistration_refund_receipt_show_default_explanation: false)

      person.update!(deregistration_kind: nil,
        deregistration_refund_receipt_show_default_explanation: nil)

      expect(person.reload.additional_info).not_to have_key(key)
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
