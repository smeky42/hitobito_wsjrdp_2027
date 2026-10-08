# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe WsjrdpDocument do
  let(:person) { people(:yp_a_1) }
  let(:other_person) { people(:yp_a_2) }

  def document(**attrs)
    @serial = (@serial || 0) + 1
    described_class.new(subject: person, key: "medical", filename: "doc.pdf", content_type: "application/pdf",
      byte_size: 1, relative_storage_file_path: "person/pdf/test/#{@serial}.pdf",
      absolute_storage_file_path: "/uploads/person/pdf/test/#{@serial}.pdf", **attrs)
  end

  def create_document(**attrs) = document(**attrs).tap(&:save!)

  # Inserts past the model's validations, so the database alone decides.
  def insert(**attrs) = document(**attrs).save!(validate: false)

  describe "defaults" do
    it "are those of the table" do
      created = create_document.reload

      expect(created).to have_attributes(status: "current", origin: "ui", key_number: 0, secondary_key_number: 0,
        secondary_key: "", comment: "", additional_info: {}, readable_by: %w[person log],
        writable_by: %w[person log], deletable_by: %w[log])
    end
  end

  describe "the current slot" do
    it "holds one current document per person and keys" do
      create_document

      expect { insert }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "takes the keys of another person, other numbers or a non-current status" do
      create_document

      expect { create_document(subject: other_person) }.not_to raise_error
      expect { create_document(key_number: 1) }.not_to raise_error
      expect { create_document(secondary_key: "signed_form", secondary_key_number: 2) }.not_to raise_error
      expect { create_document(status: "superseded", superseded_at: Time.current) }.not_to raise_error
      expect { create_document(status: "deleted", deleted_at: Time.current) }.not_to raise_error
    end

    it "holds one current derivation per original and derivation key" do
      original = create_document
      create_document(derived_from: original, derivation_key: "thumb_400")

      expect { create_document(derived_from: original, derivation_key: "pdf") }.not_to raise_error
      expect { insert(derived_from: original, derivation_key: "thumb_400") }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "does not care which document a current one replaces" do
      old = create_document(status: "superseded", superseded_at: Time.current)
      create_document(replaces: old)

      expect { create_document(key_number: 1, replaces: old) }.not_to raise_error
    end
  end

  it "registers a file once" do
    create_document(relative_storage_file_path: "person/pdf/1/a.pdf")

    expect { insert(key_number: 1, relative_storage_file_path: "person/pdf/1/a.pdf") }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  describe "check constraints" do
    it "refuse negative numbers" do
      expect { insert(key_number: -1) }.to raise_error(ActiveRecord::StatementInvalid, /chk_wsjrdp_documents_key_number/)
      expect { insert(secondary_key_number: -1) }
        .to raise_error(ActiveRecord::StatementInvalid, /chk_wsjrdp_documents_secondary_key_number/)
    end

    it "want a derivation key on a derivation" do
      original = create_document

      expect { insert(key_number: 1, derived_from: original) }
        .to raise_error(ActiveRecord::StatementInvalid, /chk_wsjrdp_documents_derivation_key/)
    end

    it "want 64 lower-case hex characters as the checksum" do
      expect { create_document(content_sha256: "a" * 64) }.not_to raise_error
      ["A" * 64, "a" * 63, "g" * 64].each do |value|
        expect { insert(key_number: 1, content_sha256: value) }
          .to raise_error(ActiveRecord::StatementInvalid, /chk_wsjrdp_documents_content_sha256/), value
      end
    end

    it "let a deleted document keep superseded_at and its predecessor" do
      old = create_document(status: "superseded", superseded_at: Time.current)

      expect { create_document(key_number: 1, status: "deleted", deleted_at: Time.current, superseded_at: Time.current, replaces: old) }
        .not_to raise_error
    end
  end

  describe "validations" do
    it "mirror the check constraints" do
      expect(document(key_number: -1)).not_to be_valid
      expect(document(secondary_key_number: -1)).not_to be_valid
      expect(document(derived_from: create_document)).not_to be_valid
      expect(document(content_sha256: "A" * 64)).not_to be_valid
      expect(document(content_sha256: nil)).to be_valid
    end
  end

  describe "deleting" do
    it "of a predecessor empties replaces of its successor" do
      old = create_document(status: "superseded", superseded_at: Time.current)
      newer = create_document(replaces: old)

      old.destroy!
      expect(newer.reload.replaces_id).to be_nil
    end

    it "of a predecessor outside Rails empties replaces too" do
      old = create_document(status: "superseded", superseded_at: Time.current)
      newer = create_document(replaces: old)

      described_class.where(id: old.id).delete_all
      expect(newer.reload.replaces_id).to be_nil
    end

    it "of an original takes its derivations with it, in Rails and outside" do
      original = create_document
      derivation = create_document(derived_from: original, derivation_key: "pdf")
      other = create_document(key_number: 1)
      other_derivation = create_document(key_number: 1, derived_from: other, derivation_key: "pdf")

      original.destroy!
      described_class.where(id: other.id).delete_all

      expect(described_class.where(id: [derivation.id, other_derivation.id])).to be_empty
    end

    it "of an API key empties the origin's key" do
      token = ServiceToken.create!(layer: groups(:root), name: "Skript", people: true, permission: "layer_read")
      created = create_document(origin: "api", origin_service_token: token)

      token.destroy!
      expect(created.reload).to have_attributes(origin: "api", origin_service_token_id: nil)
    end
  end

  describe "deleting the person" do
    let(:person) { Fabricate(:person) }

    it "deletes its documents softly and keeps them pointing at it" do
      old = create_document(status: "superseded", superseded_at: 1.day.ago)
      current = create_document(replaces: old)
      deleted = create_document(key_number: 1, status: "deleted", deleted_at: 2.days.ago)
      person_id = person.id
      deleted_at_before = deleted.deleted_at

      person.destroy!

      [old, current].each do |doc|
        expect(doc.reload).to have_attributes(status: "deleted", subject_type: "Person", subject_id: person_id)
        expect(doc.deleted_at).to be_present
        expect(doc.additional_info).to include("deleted_reason" => "subject_destroyed")
      end
      expect(old.superseded_at).to be_present
      expect(current.replaces_id).to eq(old.id)
      expect(deleted.reload.deleted_at).to be_within(1.second).of(deleted_at_before)
    end

    it "leaves no clash between two deleted persons with the same keys" do
      create_document
      person.destroy!
      second = Fabricate(:person)
      document(subject: second).save!

      expect { second.destroy! }.not_to raise_error
    end
  end
end
