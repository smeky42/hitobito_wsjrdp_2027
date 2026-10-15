# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp2027::DocumentFilename do
  let(:timestamp) { Time.zone.local(2026, 10, 11, 14, 3, 7) }

  def build(**attrs) = described_class.build(timestamp: timestamp, subject_id: 791, **attrs)

  describe ".build" do
    it "gives the name of the registration uploads with only a key" do
      expect(build(key: "medical", ext: "pdf")).to eq("2026-10-11-14-03-07--791-medical.pdf")
      expect(build(key: "registration_generated", ext: "pdf"))
        .to eq("2026-10-11-14-03-07--791-registration_generated.pdf")
    end

    it "writes numbers above 0, the secondary part, the derivation and the suffix" do
      expect(build(key: "deregistration", key_number: 2, ext: "pdf"))
        .to eq("2026-10-11-14-03-07--791-deregistration-2.pdf")
      expect(build(key: "deregistration", key_number: 2, secondary_key: "signed_form", secondary_key_number: 3,
        suffix: 1, ext: "pdf")).to eq("2026-10-11-14-03-07_1--791-deregistration-2--signed_form-3.pdf")
      expect(build(key: "deregistration", key_number: 2, secondary_key: "signed_form", secondary_key_number: 3,
        derivation_key: "thumb_400", ext: "png"))
        .to eq("2026-10-11-14-03-07--791-deregistration-2--signed_form-3~thumb_400.png")
    end

    it "writes an empty secondary key with its number and leaves out a missing extension" do
      expect(build(key: "medical", secondary_key_number: 2, ext: "pdf")).to eq("2026-10-11-14-03-07--791-medical---2.pdf")
      expect(build(key: "medical")).to eq("2026-10-11-14-03-07--791-medical")
      expect(build(key: "scan", ext: "pdf.tar.gz")).to eq("2026-10-11-14-03-07--791-scan.pdf.tar.gz")
    end
  end

  describe ".parse" do
    it "gives back what build took" do
      [
        {key: "medical", ext: "pdf"},
        {key: "registration_generated", ext: "pdf"},
        {key: "deregistration", key_number: 2, secondary_key: "signed_form", secondary_key_number: 3, suffix: 4,
         ext: "pdf"},
        {key: "medical", secondary_key_number: 2, ext: "pdf"},
        {key: "a_b_c", secondary_key: "x2", derivation_key: "thumb_400", ext: "png"},
        {key: "medical"}
      ].each do |attrs|
        parsed = described_class.parse(build(**attrs))
        expected = {suffix: 0, key_number: 0, secondary_key: "", secondary_key_number: 0, derivation_key: nil,
                    ext: nil}.merge(attrs)
        expect(parsed).to eq(expected.merge(timestamp: "2026-10-11-14-03-07", subject_id: 791))
      end
    end

    it "refuses names not of the form" do
      %w[
        2026-10-11-14-03-07--791-medical-0.pdf
        2026-10-11-14-03-07_0--791-medical.pdf
        2026-10-11-14-03-07--791-Medical.pdf
        2026-10-11-14-03-07--791-medical--.pdf
        2026-10-11-14-03-07--791-medical~.pdf
        2026-10-11-14-03-07--791-medical~a~b.pdf
        2026-10-11-14-03-07--791-medical.pdf.
        2026-10-11-14-03-07--791-medical-10-2.pdf
        2026-10-11--791-medical.pdf
      ].each { |name| expect(described_class.parse(name)).to be_nil, name }
    end
  end

  describe ".key_error" do
    it "accepts keys of a-z, 0-9 and _ starting with a letter" do
      %w[medical registration_generated good_conduct a_b thumb_400 x2 a page_2].each do |key|
        expect(described_class.key_error(key)).to be_nil, key
      end
    end

    it "agrees with KEY_FORMAT" do
      keys = %w[a medical good_conduct page_2 a_1_b x2 _a a_ a__b 2x Medical registration-generated a.b a~b] +
        ["", "a" * 40, "a" * 41]
      keys.each do |key|
        expect(key.match?(described_class::KEY_FORMAT)).to eq(described_class.key_error(key).nil?), key
      end
    end

    it "names what is wrong" do
      expect(described_class.key_error("")).to eq(:blank)
      expect(described_class.key_error("a" * 41)).to eq(:too_long)
      expect(described_class.key_error("Medical")).to eq(:invalid_characters)
      expect(described_class.key_error("2x")).to eq(:invalid_characters)
      expect(described_class.key_error("_a")).to eq(:invalid_characters)
      expect(described_class.key_error("a.b")).to eq(:invalid_characters)
      expect(described_class.key_error("a~b")).to eq(:invalid_characters)
      expect(described_class.key_error("registration-generated")).to eq(:invalid_characters)
      expect(described_class.key_error("page-2")).to eq(:invalid_characters)
      expect(described_class.key_error("a__b")).to eq(:double_separator)
      expect(described_class.key_error("a_")).to eq(:trailing_separator)
    end
  end

  describe ".extension_error" do
    it "accepts up to 20 characters of a-z, 0-9 and inner dots" do
      expect(described_class.extension_error("pdf")).to be_nil
      expect(described_class.extension_error("pdf.tar.gz")).to be_nil
      expect(described_class.extension_error("a" * 21)).to eq(:too_long)
      %w[pdf. .pdf pdf..gz PDF p-f].each { |ext| expect(described_class.extension_error(ext)).to eq(:invalid), ext }
    end
  end

  describe ".extension_from_filename" do
    it "takes the longest run of known extensions at the end" do
      expect(described_class.extension_from_filename("Scan.final.v2.PDF.tar.gz")).to eq("pdf.tar.gz")
      expect(described_class.extension_from_filename("Antrag.PDF")).to eq("pdf")
      expect(described_class.extension_from_filename("/tmp/x/.pdf")).to eq("pdf")
      expect(described_class.extension_from_filename("scan..pdf")).to eq("pdf")
      expect(described_class.extension_from_filename("bild.jpg?raw")).to be_nil
      expect(described_class.extension_from_filename("scan.pdf.")).to be_nil
      expect(described_class.extension_from_filename("README")).to be_nil
    end

    it "keeps to 20 characters" do
      expect(described_class.extension_from_filename("a.jpeg.xlsx.docx.pdf.tar.gz")).to eq("xlsx.docx.pdf.tar.gz")
    end
  end

  it "finds the extension of a content type" do
    expect(described_class.extension_for_type("application/pdf")).to eq("pdf")
    expect(described_class.extension_for_type("image/jpeg")).to eq("jpg")
    expect(described_class.extension_for_type("text/plain; charset=utf-8")).to eq("txt")
    expect(described_class.extension_for_type("application/octet-stream")).to be_nil
  end
end
