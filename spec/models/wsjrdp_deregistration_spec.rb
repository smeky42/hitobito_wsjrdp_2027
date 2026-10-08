# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe WsjrdpDeregistration do
  let(:person) { people(:yp_a_1) }

  def deregistration(**attrs) = WsjrdpDeregistration.create!(person_id: person.id, number: 1, **attrs)

  def event(deregistration, **attrs) = WsjrdpDeregistrationEvent.create!(deregistration_id: deregistration.id, event: "update", **attrs)

  describe "defaults" do
    it "are those of the table" do
      created = deregistration.reload

      expect(created).to have_attributes(status: "recorded", kind: "withdrawal", actual_compensation_currency: "EUR",
        show_contractual_compensation: true,
        form_options: {}, form_snapshot: {}, comment: "", additional_info: {}, replaces_id: nil, closed_at: nil)
      expect(created.created_at).to be_present
    end

    it "set created_at in the database" do
      described_class.insert_all([{person_id: person.id, number: 1}], record_timestamps: false)

      expect(described_class.find_by!(person_id: person.id).created_at).to be_present
    end

    it "keep the compensation as a decimal" do
      expect(deregistration(actual_compensation: "1234.567").reload.actual_compensation).to eq(BigDecimal("1234.567"))
    end
  end

  describe "number" do
    it "is unique per person, whatever the status" do
      deregistration(status: "superseded")

      expect { described_class.new(person_id: person.id, number: 1).save!(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique)
      expect { deregistration(number: 2) }.not_to raise_error
      expect { described_class.create!(person_id: people(:yp_a_2).id, number: 1) }.not_to raise_error
    end

    it "starts at 1, in the database and in the model" do
      expect(described_class.new(person_id: person.id, number: 0)).not_to be_valid
      expect { described_class.new(person_id: person.id, number: 0).save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /chk_wsjrdp_deregistrations_number/)
    end
  end

  describe "deleting" do
    it "of a replaced row empties replaces of its replacement" do
      old = deregistration(status: "superseded")
      newer = deregistration(number: 2, replaces_id: old.id)

      old.destroy!
      expect(newer.reload.replaces_id).to be_nil
    end

    it "of a document empties the reference to it" do
      document = WsjrdpDocument.create!(subject: person, key: "deregistration", key_number: 1, secondary_key: "form",
        filename: "form.pdf", content_type: "application/pdf", byte_size: 1,
        relative_storage_file_path: "person/pdf/test/form.pdf", absolute_storage_file_path: "/uploads/form.pdf")
      row = deregistration(sent_form_document_id: document.id, signed_form_document_id: document.id)

      document.destroy!
      expect(row.reload).to have_attributes(sent_form_document_id: nil, signed_form_document_id: nil)
    end

    it "of a row takes its events with it, in Rails and outside" do
      first = deregistration
      second = deregistration(number: 2)
      events = [event(first), event(second, event: "create")]

      first.destroy!
      described_class.where(id: second.id).delete_all

      expect(WsjrdpDeregistrationEvent.where(id: events.map(&:id))).to be_empty
    end

    it "of the person keeps the row with its person_id" do
      fabricated = Fabricate(:person)
      row = described_class.create!(person_id: fabricated.id, number: 1)

      fabricated.destroy!
      expect(row.reload.person_id).to eq(fabricated.id)
    end
  end

  describe WsjrdpDeregistrationEvent do
    it "has the defaults of the table" do
      created = event(deregistration).reload

      expect(created).to have_attributes(actor_type: "Person", actor_id: nil, action: nil, from_status: nil,
        to_status: nil, comment: "", field_changes: {}, additional_info: {})
      expect(created.occurred_at).to be_present
      expect(created.created_at).to be_present
    end

    it "knows create, update and notify only" do
      row = deregistration

      %w[create update notify].each do |name|
        expect(WsjrdpDeregistrationEvent.new(deregistration_id: row.id, event: name)).to be_valid
      end
      expect(WsjrdpDeregistrationEvent.new(deregistration_id: row.id, event: "closed")).not_to be_valid
    end

    it "keeps changes, action and the status move" do
      created = event(deregistration, action: "form_sent", from_status: "form_created", to_status: "form_sent",
        field_changes: {"form_sent_at" => [nil, "2026-10-08T10:00:00+02:00"]}).reload

      expect(created.field_changes).to eq("form_sent_at" => [nil, "2026-10-08T10:00:00+02:00"])
      expect(created).to have_attributes(action: "form_sent", from_status: "form_created", to_status: "form_sent")
    end
  end
end
