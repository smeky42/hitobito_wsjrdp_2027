# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe WsjrdpPaymentNotice do
  let(:person) { people(:yp_a_1) }

  def notice(**attrs)
    described_class.create!(subject_id: person.id, amount: "-100", payment_code: "RF00AAAABBBBCCCC",
      description: "Rückzahlung", **attrs)
  end

  def document
    WsjrdpDocument.create!(subject: person, key: "deregistration", secondary_key: "receipt",
      filename: "receipt.pdf", content_type: "application/pdf", byte_size: 1,
      relative_storage_file_path: "person/pdf/test/receipt.pdf", absolute_storage_file_path: "/uploads/receipt.pdf")
  end

  def pre_notification(**attrs)
    WsjrdpDirectDebitPreNotification.create!(payment_initiation: WsjrdpPaymentInitiation.create!, subject: person,
      author: person, amount_cents: 1000, description: "Einzug", dbtr_name: "Muster",
      dbtr_iban: "DE02120300000000202051", **attrs)
  end

  describe "defaults" do
    it "are those of the table" do
      created = notice.reload

      expect(created).to have_attributes(subject_type: "Person", author_type: "Person", status: "created",
        booked_amount: 0, amount_currency: "EUR", receipt_options: {}, receipt_snapshot: {}, comment: "",
        additional_info: {}, replaces_id: nil, ref_type: nil, announced_at: nil, closed_at: nil)
      expect(created.created_at).to be_present
    end

    it "set created_at in the database" do
      described_class.insert_all([{subject_id: person.id, amount: 1, payment_code: "RF00", description: "x"}],
        record_timestamps: false)

      expect(described_class.find_by!(payment_code: "RF00").created_at).to be_present
    end
  end

  describe "amounts" do
    it "keep their sign and three decimals" do
      expect(notice(amount: "-1234.567").reload.amount).to eq(BigDecimal("-1234.567"))
    end

    it "leave open what is not booked, either way" do
      expect(notice(amount: "-100", booked_amount: "-40").open_amount).to eq(BigDecimal("-60"))
      expect(notice(amount: "250", booked_amount: "300").open_amount).to eq(BigDecimal("-50"))
      expect(notice(amount: "250", booked_amount: "250").open_amount).to be_zero
    end
  end

  it "takes the same payment code twice" do
    notice

    expect { notice }.not_to raise_error
  end

  describe "deleting" do
    it "of a replaced notice empties replaces of its replacement" do
      old = notice(status: "canceled")
      newer = notice(replaces_id: old.id)

      old.destroy!
      expect(newer.reload.replaces_id).to be_nil
    end

    it "of the receipt empties the reference to it" do
      receipt = document
      created = notice(receipt_document_id: receipt.id)

      receipt.destroy!
      expect(created.reload.receipt_document_id).to be_nil
    end

    it "of a notice empties the reference of its accounting entries" do
      created = notice
      entry = AccountingEntry.create!(subject: person, author: person, amount_cents: -10_000, description: "Rückzahlung",
        value_date: Time.zone.today, booking_date: Time.zone.today, payment_notice_id: created.id)

      created.destroy!
      expect(entry.reload.payment_notice_id).to be_nil
    end

    it "of the person keeps the notice" do
      fabricated = Fabricate(:person)
      created = described_class.create!(subject_id: fabricated.id, amount: 1, payment_code: "RF00", description: "x")

      fabricated.destroy!
      expect(created.reload.subject_id).to eq(fabricated.id)
    end
  end

  describe "direct debit pre-notifications" do
    it "have no reference, predecessor or document by default" do
      expect(pre_notification.reload).to have_attributes(ref_type: nil, ref_id: nil, replaces_id: nil,
        receipt_document_id: nil)
    end

    it "keep a reference to what they are for" do
      deregistration = WsjrdpDeregistration.create!(person_id: person.id, number: 1)

      expect(pre_notification(ref_type: "WsjrdpDeregistration", ref_id: deregistration.id).reload)
        .to have_attributes(ref_type: "WsjrdpDeregistration", ref_id: deregistration.id)
    end

    it "lose their predecessor and document when those are deleted" do
      old = pre_notification
      receipt = document
      newer = pre_notification(replaces_id: old.id, receipt_document_id: receipt.id)

      old.destroy!
      receipt.destroy!
      expect(newer.reload).to have_attributes(replaces_id: nil, receipt_document_id: nil)
    end
  end
end
