# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The words the Abmeldung page's flash and the person log use for a value of a
# deregistration.
describe Wsjrdp2027::DeregistrationWording do
  describe ".describe" do
    it "names the kind, an absent one as the withdrawal it stands for" do
      expect(described_class.describe("kind", "termination")).to eq("Kündigung (durch das Kontingent)")
      expect(described_class.describe("kind", "withdrawal")).to eq("Abmeldung (durch die Person)")
      expect(described_class.describe("kind", "cancellation")).to eq("Storno der Registrierung (kein Vertrag)")
      expect(described_class.describe("kind", nil)).to eq("Abmeldung (durch die Person)")
    end

    it "reads a flag as shown or hidden, an absent one as shown" do
      described_class::FLAGS.each do |flag|
        expect(described_class.describe(flag, nil)).to eq("anzeigen")
        expect(described_class.describe(flag, true)).to eq("anzeigen")
        expect(described_class.describe(flag, "0")).to eq("ausblenden")
        expect(described_class.describe(flag, false)).to eq("ausblenden")
      end
    end

    it "words a day the German way, from an ISO string or a Date, an en dash where there is none" do
      expect(described_class.describe("form_created_date", "2026-09-27")).to eq("27.09.2026")
      expect(described_class.describe("reply_due_date", Date.new(2026, 10, 1))).to eq("01.10.2026")
      expect(described_class.describe("reply_due_date", nil)).to eq("–")
    end

    it "says whether the receipt's figures are stored, and names its maker" do
      expect(described_class.describe("receipt_snapshot", {"a" => "1"})).to eq("gespeichert")
      expect(described_class.describe("receipt_snapshot", nil)).to eq("–")
      expect(described_class.describe("receipt_created_by_id", people(:admin).id)).to eq(people(:admin).to_s)
    end

    it "says the text as it stands and an en dash where there is none" do
      expect(described_class.describe("refund_receipt_text", "Hallo\nTeam")).to eq("Hallo Team")
      expect(described_class.describe("refund_receipt_text", nil)).to eq("–")
    end
  end

  describe ".same?" do
    it "reads a stored default and an absent value as the same" do
      expect(described_class.same?("kind", nil, "withdrawal")).to be(true)
      expect(described_class.same?("form_show_contractual_compensation", nil, true)).to be(true)
      expect(described_class.same?("form_show_contractual_compensation", nil, false)).to be(false)
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

  describe ".key and .person_attr" do
    it "go between the person's accessor name and the key" do
      expect(described_class.key(:deregistration_kind)).to eq("kind")
      expect(described_class.key("deregistration_refund_receipt_text")).to eq("refund_receipt_text")
      expect(described_class.person_attr("kind")).to eq(:deregistration_kind)
    end

    it "answer nothing for a name not worded here" do
      expect(described_class.key(:deregistration_issue)).to be_nil
      expect(described_class.key(:status)).to be_nil
    end
  end
end
