# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# What the Abmeldung page writes down beyond its dates and amounts, in one
# sub-object of people.additional_info: the kind of deregistration and what the
# page's two documents carry. An absent value is the default, so only what
# differs from one is ever written.
describe Wsjrdp2027::DeregistrationRecord do
  let(:person) { people(:yp_a_1) }
  let(:key) { described_class::KEY }

  describe ".load" do
    it "reads the defaults where the person carries nothing" do
      record = described_class.load(person)

      expect(record.kind).to be_nil
      expect(record.kind_or_default).to eq("withdrawal")
      expect(record).not_to be_termination
      expect(record.form_show_contractual_compensation).to be_nil
      expect(record).to be_form_show_contractual_compensation
      expect(record.refund_receipt_text).to be_nil
      expect(record.refund_receipt_show_default_explanation).to be_nil
      expect(record).to be_refund_receipt_show_default_explanation
      expect(record.to_h).to eq({})
    end

    it "reads what is stored" do
      person.update_column(:additional_info, {key => {
        "kind" => "termination",
        "form_show_contractual_compensation" => false,
        "refund_receipt_text" => "Hallo Team",
        "refund_receipt_show_default_explanation" => false
      }})

      record = described_class.load(person.reload)

      expect(record.kind).to eq("termination")
      expect(record).to be_termination
      expect(record.form_show_contractual_compensation).to be(false)
      expect(record).not_to be_form_show_contractual_compensation
      expect(record.refund_receipt_text).to eq("Hallo Team")
      expect(record.refund_receipt_show_default_explanation).to be(false)
      expect(record).not_to be_refund_receipt_show_default_explanation
    end

    # A key the record does not know is none of its business: it is left where
    # it is and never raised on.
    it "ignores a key it does not know" do
      person.update_column(:additional_info,
        {key => {"kind" => "termination", "something_else" => "x"}})

      record = described_class.load(person.reload)

      expect(record.kind).to eq("termination")
      expect(record.to_h).to eq("kind" => "termination")
    end

    it "reads a stored value that is no hash as nothing stored" do
      person.update_column(:additional_info, {key => "termination"})

      expect(described_class.load(person.reload).to_h).to eq({})
    end
  end

  describe "#to_h" do
    it "writes nothing for a value that is the default" do
      record = described_class.new(kind: "", refund_receipt_text: "   ")

      expect(record.to_h).to eq({})
    end

    it "writes a flag that was switched off" do
      expect(described_class.new(form_show_contractual_compensation: false).to_h)
        .to eq("form_show_contractual_compensation" => false)
    end

    # A flag that is on reads the same as an absent one, and so does the
    # withdrawal: neither is written, so a form that sends the defaults again
    # changes nothing.
    it "writes nothing for a flag that is on" do
      expect(described_class.new(refund_receipt_show_default_explanation: true).to_h).to eq({})
    end

    it "writes nothing for the withdrawal" do
      expect(described_class.new(kind: "withdrawal").to_h).to eq({})
    end

    it "tells a stored default from a change" do
      expect(described_class.same?("kind", "withdrawal", nil)).to be(true)
      expect(described_class.same?("form_show_contractual_compensation", true, nil)).to be(true)
      expect(described_class.same?("kind", "withdrawal", "termination")).to be(false)
      expect(described_class.same?("refund_receipt_text", nil, "Hallo Team")).to be(false)
    end

    it "strips what surrounds the text" do
      expect(described_class.new(refund_receipt_text: "  Hallo Team\n\n").to_h)
        .to eq("refund_receipt_text" => "Hallo Team")
    end

    it "lists the values in the order the form asks for them" do
      record = described_class.new(kind: "termination",
        form_show_contractual_compensation: false,
        refund_receipt_text: "Hallo Team",
        refund_receipt_show_default_explanation: false)

      expect(record.to_h.keys).to eq(described_class::ATTRS)
    end
  end

  describe "#store" do
    it "writes the sub-object into a copy of the column, without saving" do
      before_info = person.additional_info

      described_class.new(kind: "termination").store(person)

      expect(person.additional_info[key]).to eq("kind" => "termination")
      expect(person.additional_info).not_to be(before_info)
      expect(before_info).not_to have_key(key)
      expect(person).to be_changed
      expect(Person.find(person.id).additional_info).not_to have_key(key)
    end

    it "keeps what else the column carries" do
      person.update!(deregistration_issue: "Ticket 1")

      described_class.new(kind: "termination").store(person)

      expect(person.additional_info["deregistration_issue"]).to eq("Ticket 1")
    end

    it "drops the key where every value is the default" do
      person.update_column(:additional_info, {key => {"kind" => "termination"}})
      person.reload

      described_class.new.store(person)

      expect(person.additional_info).not_to have_key(key)
    end

    it "answers itself" do
      record = described_class.new
      expect(record.store(person)).to be(record)
    end
  end

  describe "the kind" do
    it "takes the two kinds" do
      described_class::KINDS.each do |kind|
        expect(described_class.new(kind: kind)).to be_valid
      end
    end

    it "takes no kind at all" do
      expect(described_class.new).to be_valid
      expect(described_class.new(kind: "")).to be_valid
    end

    it "refuses a third kind" do
      record = described_class.new(kind: "foo")

      expect(record).not_to be_valid
      expect(record.errors[:kind]).to be_present
    end
  end

  # The words the Abmeldung page's flash and the person log both use.
  describe ".describe" do
    it "names the kind, an absent one as the withdrawal it stands for" do
      expect(described_class.describe("kind", "termination"))
        .to eq("Kündigung (durch das Kontingent)")
      expect(described_class.describe("kind", "withdrawal"))
        .to eq("Abmeldung (durch die Person)")
      expect(described_class.describe("kind", nil)).to eq("Abmeldung (durch die Person)")
    end

    it "reads a flag as shown or hidden, an absent one as shown" do
      described_class::FLAGS.each do |flag|
        expect(described_class.describe(flag, nil)).to eq("anzeigen")
        expect(described_class.describe(flag, true)).to eq("anzeigen")
        expect(described_class.describe(flag, false)).to eq("ausblenden")
      end
    end

    it "says the text as it stands and an en dash where there is none" do
      expect(described_class.describe("refund_receipt_text", "Hallo\nTeam"))
        .to eq("Hallo Team")
      expect(described_class.describe("refund_receipt_text", nil)).to eq("–")
    end
  end

  describe ".describe_change" do
    it "leads with what the person calls the value" do
      expect(described_class.describe_change("kind", nil, "termination"))
        .to eq("Art: Abmeldung (durch die Person) → Kündigung (durch das Kontingent)")
      expect(described_class.describe_change("refund_receipt_text", "Hallo Team", nil))
        .to eq("Text im Beleg: Hallo Team → –")
    end
  end

  describe ".sub_key" do
    it "answers the value a person's accessor name stands for" do
      expect(described_class.sub_key(:deregistration_kind)).to eq("kind")
      expect(described_class.sub_key("deregistration_refund_receipt_text"))
        .to eq("refund_receipt_text")
    end

    it "answers nothing for a name that is not the record's" do
      expect(described_class.sub_key(:deregistration_issue)).to be_nil
      expect(described_class.sub_key(:status)).to be_nil
    end
  end

  describe ".person_attr" do
    it "answers what the person calls the value" do
      expect(described_class.person_attr("kind")).to eq(:deregistration_kind)
    end
  end
end
