# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe WsjrdpDocumentKind do
  let(:good_conduct) { wsjrdp_document_kinds(:good_conduct) }

  def kind(**attrs) = described_class.new({subject_type: "Person", key: "note", label: "Notiz"}.merge(attrs))

  def problems(**attrs)
    record = kind(**attrs)
    record.validate
    record.errors.attribute_names
  end

  it "finds the kind of a document's keys exactly" do
    expect(described_class.for(subject_type: "Person", key: "medical")).to eq(wsjrdp_document_kinds(:medical))
    expect(described_class.for(subject_type: "Person", key: "medical", secondary_key: "page")).to be_nil
    expect(described_class.for_document(WsjrdpDocument.new(subject_type: "Person", key: "sepa", secondary_key: "")))
      .to eq(wsjrdp_document_kinds(:sepa))
  end

  it "accepts what the registration kinds hold" do
    expect(described_class.all).to all(be_valid)
  end

  it "checks keys, rights entries and file restrictions" do
    expect(problems(key: "Letter")).to eq([:key])
    expect(problems(secondary_key: "page-2")).to eq([:secondary_key])
    %w[finance_ _log fin__audit Log a-b].each do |entry|
      expect(problems(readable_by: ["log", entry])).to eq([:readable_by]), entry
    end
    expect(problems(readable_by: ["a" * 30])).to be_empty
    expect(problems(readable_by: ["a" * 31])).to eq([:readable_by])
    expect(problems(readable_by: %w[log finance_]))
      .to eq([:readable_by])
    expect(problems(content_types: %w[application/pdf image/* pdf])).to eq([:content_types])
    expect(problems(extensions: %w[pdf .pdf])).to eq([:extensions])
    expect(problems(max_upload_size_mb: 0)).to eq([:max_upload_size_mb])
    expect(problems(subject_type: "Group")).to eq([:subject_type])
    expect(problems(key: "medical")).to eq([:key])
    expect(problems(people_column_name: "first_name")).to eq([:people_column_name])
    expect(problems(people_column_name: "upload_medical_pdf")).to eq([:people_column_name])
    expect(problems(people_column_name: "upload_medical_pdf", subject_type: "Group")).to include(:people_column_name)
    expect(kind(people_column_name: " ").people_column_name).to be_nil
  end

  it "checks the role rules" do
    expect(problems(role_rules: {})).to eq([:role_rules])
    [
      ["x"], [{"who" => []}], [{"roles" => ["XX"]}], [{"roles" => "YP"}], [{"offer_to" => ["Log"]}],
      [{"not_for_status" => ["nowhere"]}], [{"required" => "yes"}], [{"missing_tag" => {"tag" => ""}}],
      [{"missing_tag" => {"tag" => "t", "from_status" => ["nowhere"]}}],
      [{"missing_tag" => {"tag" => "t", "remove_on_upload" => 1}}], [{"missing_tag" => {"tag" => "t", "x" => 1}}]
    ].each { |rules| expect(problems(role_rules: rules)).to eq([:role_rules]), rules.inspect }

    expect(problems(role_rules: [{"roles" => %w[YP EXT], "offer_to" => %w[update], "not_for_status" => %w[registered],
                                  "required" => true, "missing_tag" => {"tag" => "t", "from_status" => %w[reviewed], "remove_on_upload" => true}},
      {}])).to be_empty
  end

  it "takes the first rule for the person's contingent role" do
    expect(good_conduct.rule_for(people(:ul_a_1))).to include("required" => true)
    expect(good_conduct.rule_for(people(:ist_a_1))).to include("required" => false)
    expect(good_conduct.rule_for(people(:yp_a_1))).to be_nil
    expect(wsjrdp_document_kinds(:medical).rule_for(people(:yp_a_1))).to be_present
  end

  it "says whether the kind is required and which tag marks it missing" do
    expect(good_conduct.required_for?(people(:ul_a_1))).to be(true)
    expect(good_conduct.required_for?(people(:ist_a_1))).to be(false)
    expect(good_conduct.required_for?(people(:yp_a_1))).to be(false)
    expect(good_conduct.missing_tag_for(people(:ist_a_1))).to include("tag" => "eFZ-Einsicht-fehlt")
    expect(good_conduct.missing_tag_for(people(:yp_a_1))).to be_nil
  end

  it "offers the kind to whom the rule names, not in the statuses it excludes" do
    medical = wsjrdp_document_kinds(:medical)
    person = people(:yp_a_1)
    person.status = "in_review"

    expect(medical.offered?(person, ability: Ability.new(people(:cmt_leader)))).to be(true)
    expect(medical.offered?(person, ability: Ability.new(people(:yp_a_2)))).to be(false)
    expect(good_conduct.offered?(person, ability: Ability.new(people(:cmt_leader)))).to be(false)

    person.status = "registered"
    expect(medical.offered?(person, ability: Ability.new(people(:cmt_leader)))).to be(false)
  end

  it "names why an upload is refused" do
    pdf = {content_type: "application/pdf", filename: "a.PDF", byte_size: 10}
    medical = wsjrdp_document_kinds(:medical)

    expect(medical.upload_error(**pdf)).to be_nil
    expect(medical.upload_error(**pdf, content_type: "image/png")).to eq([:content_type, {types: "application/pdf"}])
    expect(medical.upload_error(**pdf, filename: "a.png")).to eq([:extension, {extensions: "pdf"}])

    medical.max_upload_size_mb = 1
    expect(medical.upload_error(**pdf, byte_size: 2.megabytes)).to eq([:too_large, {size: 1}])

    images = kind(content_types: %w[image/*])
    expect(images.upload_error(content_type: "image/jpeg; charset=binary", filename: "x", byte_size: 1)).to be_nil
    expect(kind.upload_error(content_type: "x/y", filename: "x", byte_size: 1)).to be_nil
  end
end
