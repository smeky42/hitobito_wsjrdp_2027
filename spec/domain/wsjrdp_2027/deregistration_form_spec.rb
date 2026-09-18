# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The declaration a person signs to withdraw from the contract: the scripts'
# Abmelde-Formular, prefilled with what the Abmeldung page knows and left as a
# line to fill in by hand where it knows nothing.
describe Wsjrdp2027::DeregistrationForm do
  let(:person) { people(:yp_a_1) }
  let(:admin) { people(:admin) }
  let(:form) { described_class.new(person.reload) }

  def booked_entry(amount_cents:)
    AccountingEntry.create!(subject: person, author: admin, amount_cents: amount_cents,
      amount_currency: "EUR", description: "Teilnahmebeitrag",
      value_date: Date.new(2026, 2, 1), booking_date: Date.new(2026, 2, 1))
  end

  before do
    booked_entry(amount_cents: 40_000)
    person.update!(deregistration_effective_date: Date.new(2026, 10, 31),
      sepa_name: "Kim Alex Muster-Beispiel",
      sepa_iban: "DE02120300000000202051")
  end

  describe "who the document is about" do
    it "names the role, the id and the short name" do
      expect(form.role_id_name).to eq("YP #{person.id} YP1 UnitA")
      expect(form.to_sys_inputs[:role_id_name]).to eq("YP #{person.id} YP1 UnitA")
    end

    it "names the person and what the document is in the file name" do
      expect(form.file_name).to eq("WSJ27 Abmeldung YP #{person.id} YP1 UnitA.pdf")
    end

    it "replaces what a file name must not carry" do
      person.update!(last_name: "Muster/Beispiel")

      expect(described_class.new(person.reload).file_name).to include("Muster_Beispiel")
    end
  end

  # The form is the person's own declaration of a withdrawal, and it names the
  # day the withdrawal takes effect.
  describe "#available?" do
    it "is offered for a withdrawal with a date" do
      expect(form).to be_available
      expect(form.unavailable_reasons).to eq([])
    end

    it "is not offered for a termination by the contingent" do
      person.update!(deregistration_kind: "termination")
      form = described_class.new(person.reload)

      expect(form).not_to be_available
      expect(form.unavailable_reasons).to eq([:termination])
    end

    it "is not offered while the day it takes effect is unknown" do
      person.update!(deregistration_effective_date: nil)
      form = described_class.new(person.reload)

      expect(form).not_to be_available
      expect(form.unavailable_reasons).to eq([:no_effective_date])
    end

    it "names both reasons where both apply" do
      person.update!(deregistration_kind: "termination", deregistration_effective_date: nil)

      expect(described_class.new(person.reload).unavailable_reasons)
        .to eq([:termination, :no_effective_date])
    end
  end

  # Who signs: the person, and the guardians where somebody signs with them --
  # for a youth participant and for anybody under 18.
  describe "#contract_names" do
    before do
      person.update!(additional_contact_name_a: "Alex Muster",
        additional_contact_name_b: "Sam Muster")
    end

    it "carries the youth participant and both guardians" do
      expect(described_class.new(person.reload).contract_names)
        .to eq(["YP1 UnitA", "Alex Muster", "Sam Muster"])
    end

    it "carries the one guardian where only one signs" do
      person.update!(additional_contact_single: true)

      expect(described_class.new(person.reload).contract_names)
        .to eq(["YP1 UnitA", "Alex Muster"])
    end

    it "leaves a blank guardian out" do
      person.update!(additional_contact_name_b: "   ")

      expect(described_class.new(person.reload).contract_names)
        .to eq(["YP1 UnitA", "Alex Muster"])
    end

    it "names an adult on their own" do
      ist = people(:ist_a_1)
      ist.update!(birthday: 30.years.ago.to_date, additional_contact_name_a: "Alex Muster",
        additional_contact_name_b: "Sam Muster")

      expect(described_class.new(ist.reload).contract_names).to eq(["IST1 IstA"])
    end

    it "names the guardians of a minor unit leader" do
      ul = people(:ul_a_1)
      ul.update!(birthday: 17.years.ago.to_date, additional_contact_name_a: "Alex Muster",
        additional_contact_name_b: "Sam Muster")

      expect(described_class.new(ul.reload).contract_names)
        .to eq(["UL1 UnitA", "Alex Muster", "Sam Muster"])
    end

    # A person without a birthday is not of legal age, the way the registration
    # contract reads it.
    it "counts a missing birthday as not of legal age" do
      ist = people(:ist_a_1)
      ist.update!(additional_contact_name_a: "Alex Muster")

      expect(ist.birthday).to be_nil
      expect(described_class.new(ist.reload).contract_names).to eq(["IST1 IstA", "Alex Muster"])
    end

    it "travels as JSON" do
      person.update!(additional_contact_single: true)
      inputs = described_class.new(person.reload).to_sys_inputs

      expect(JSON.parse(inputs[:contract_names])).to eq(["YP1 UnitA", "Alex Muster"])
    end
  end

  describe "the dates" do
    it "are empty while nothing is known" do
      person.update!(deregistration_effective_date: nil)
      form = described_class.new(person.reload)

      expect(form.birthday_text).to eq("")
      expect(form.cancellation_date_text).to eq("")
      expect(form.to_sys_inputs[:birthday_de]).to eq("")
      expect(form.to_sys_inputs[:cancellation_date_de]).to eq("")
    end

    it "are written the German way" do
      person.update!(birthday: Date.new(2010, 5, 4))
      form = described_class.new(person.reload)

      expect(form.birthday_text).to eq("04.05.2010")
      expect(form.cancellation_date_text).to eq("31.10.2026")
      expect(form.to_sys_inputs[:birthday_de]).to eq("04.05.2010")
      expect(form.to_sys_inputs[:cancellation_date_de]).to eq("31.10.2026")
    end
  end

  describe "the amounts" do
    it "leaves what follows from a compensation open while none is agreed" do
      expect(person.deregistration_actual_compensation_cents).to be_nil
      expect(form.actual_compensation_cents).to be_nil
      expect(form.refund_cents).to be_nil
      expect(form.missing_cents).to be_nil

      inputs = form.to_sys_inputs
      expect(inputs[:actual_compensation_cents]).to eq("")
      expect(inputs[:refund_amount_cents]).to eq("")
      expect(inputs[:missing_amount_cents]).to eq("")
      expect(inputs[:actual_compensation_display]).to eq("")
      expect(inputs[:refund_amount_display]).to eq("")
      expect(inputs[:missing_amount_display]).to eq("")
    end

    it "pays back what is left of a compensation below what was paid" do
      person.update!(deregistration_actual_compensation_cents: 10_000)
      form = described_class.new(person.reload)

      expect(form.amount_paid_cents).to eq(40_000)
      expect(form.actual_compensation_cents).to eq(10_000)
      expect(form.refund_cents).to eq(30_000)
      expect(form.missing_cents).to eq(0)
    end

    it "asks for what is missing where the compensation is the larger amount" do
      person.update!(deregistration_actual_compensation_cents: 50_000)
      form = described_class.new(person.reload)

      expect(form.refund_cents).to eq(0)
      expect(form.missing_cents).to eq(10_000)
    end

    # The bracket of section 7.2 T&R stands in grey below the compensation --
    # unless the document is asked for without it.
    it "states the bracket of the travel conditions" do
      expect(form.contractual_compensation_cents)
        .to eq(person.deregistration_contractual_compensation_cents)
      expect(form.contractual_compensation_cents).to be > 0
    end

    it "leaves the bracket out where it is switched off" do
      form = described_class.new(person.reload, show_contractual_compensation: false)

      expect(form.show_contractual_compensation?).to be(false)
      expect(form.contractual_compensation_cents).to be_nil
      expect(form.to_sys_inputs[:contractual_compensation_cents]).to eq("")
      expect(form.to_sys_inputs[:contractual_compensation_display]).to eq("")
    end

    # Whether the bracket is named belongs to the deregistration, so without a
    # keyword the person's own flag decides -- and an absent flag states it.
    it "follows the person's flag where the caller asks for nothing" do
      expect(person.additional_info).not_to have_key("deregistration_record")
      expect(form.show_contractual_compensation?).to be(true)

      person.update!(deregistration_form_show_contractual_compensation: false)
      form = described_class.new(person.reload)

      expect(form.show_contractual_compensation?).to be(false)
      expect(form.to_sys_inputs[:contractual_compensation_cents]).to eq("")
    end

    it "lets a caller that says so outright outrank the person's flag" do
      person.update!(deregistration_form_show_contractual_compensation: false)
      form = described_class.new(person.reload, show_contractual_compensation: true)

      expect(form.show_contractual_compensation?).to be(true)
      expect(form.contractual_compensation_cents)
        .to eq(person.deregistration_contractual_compensation_cents)
    end
  end

  # The scripts' format: ",—" for whole euros, a non-breaking space before the
  # euro sign.
  describe "the amounts as they are written" do
    it "writes whole euros with a dash" do
      expect(form.to_sys_inputs[:amount_paid_display]).to eq("400,— €")
    end

    it "writes the cents where there are any" do
      booked_entry(amount_cents: 2_345)

      expect(described_class.new(person.reload).to_sys_inputs[:amount_paid_display])
        .to eq("423,45 €")
    end

    it "writes a compensation of zero as an amount as well" do
      person.update!(deregistration_actual_compensation_cents: 0)
      inputs = described_class.new(person.reload).to_sys_inputs

      expect(inputs[:actual_compensation_cents]).to eq("0")
      expect(inputs[:actual_compensation_display]).to eq("0,— €")
    end
  end

  describe "#to_sys_inputs" do
    it "hands every value to typst as a String" do
      inputs = form.to_sys_inputs

      expect(inputs.values).to all(be_a(String))
      expect(inputs[:hitobitoid]).to eq(person.id.to_s)
      expect(inputs[:full_name]).to eq("YP1 UnitA")
      expect(inputs[:amount_paid_cents]).to eq("40000")
    end

    # Normalized the way the SEPA exports write it, so what is read off the page
    # can be typed into online banking as it stands.
    it "carries the account a refund goes to" do
      person.update!(sepa_iban: "de02 1203 0000 0000 2020 51")
      inputs = described_class.new(person.reload).to_sys_inputs

      expect(inputs[:refund_iban]).to eq("DE02120300000000202051")
      expect(inputs[:refund_account_holder]).to eq("Kim Alex Muster-Beispiel")
    end

    it "sends the key set the template reads" do
      expect(form.to_sys_inputs.keys).to eq(%i[
        role_id_name hitobitoid full_name birthday_de cancellation_date_de contract_names
        amount_paid_cents actual_compensation_cents contractual_compensation_cents
        refund_amount_cents missing_amount_cents
        amount_paid_display actual_compensation_display contractual_compensation_display
        refund_amount_display missing_amount_display
        refund_iban refund_account_holder
      ])
    end
  end

  describe "#to_pdf" do
    it "compiles the template" do
      pdf = form.to_pdf

      expect(pdf).to start_with("%PDF")
      expect(pdf.bytesize).to be > 1_000
    end

    it "compiles with a refund" do
      person.update!(deregistration_actual_compensation_cents: 10_000)

      expect(described_class.new(person.reload).to_pdf).to start_with("%PDF")
    end

    it "compiles with an amount that is still open" do
      person.update!(deregistration_actual_compensation_cents: 50_000)

      expect(described_class.new(person.reload).to_pdf).to start_with("%PDF")
    end

    # Whatever somebody typed into a name is text, never markup: the compile
    # must neither fail nor evaluate anything.
    it "compiles a name that looks like typst markup, as text" do
      person.update!(first_name: "#emph[x] *y* $z$ ] \" ; #eval(\"1\")")

      expect(described_class.new(person.reload).to_pdf).to start_with("%PDF")
    end
  end

  # The picture the Abmeldung page previews the document with.
  describe "#to_png" do
    it "draws the first page" do
      png = form.to_png

      expect(png).to start_with(Wsjrdp2027::TypstDocument::PNG_SIGNATURE)
      expect(png.bytesize).to be > 1_000
    end
  end
end
