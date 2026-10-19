# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp2027::UploadFilename do
  describe ".refusal" do
    def refusal(name) = described_class.refusal(name)

    it "lets an ordinary name through, umlauts, Hebrew and its marks included" do
      expect(refusal("Mein Vertrag (unterschrieben) 2026.pdf")).to be_nil
      expect(refusal("\u05E9\u05DC\u05D5\u05DD\u200F.pdf")).to be_nil
      expect(refusal("\u2067\u0645\u0631\u062D\u0628\u0627\u2069.pdf")).to be_nil
    end

    it "refuses a name of 500 bytes or more as given, as too long" do
      expect(refusal("#{"a" * 495}.pdf")).to be_nil
      expect(refusal("#{"a" * 496}.pdf")).to eq(:too_long)
      expect(refusal("#{"ü" * 248}.pdf")).to eq(:too_long)
    end

    it "refuses invalid UTF-8, control characters, U+202E and path separators" do
      expect(refusal("bad\xFF.pdf".b)).to eq(:invalid_encoding)
      expect(refusal("a\u0000b.pdf")).to eq(:control_character)
      expect(refusal("a\tb.pdf")).to eq(:control_character)
      expect(refusal("a\u0085b.pdf")).to eq(:control_character)
      expect(refusal("rechnung\u202Efdp.exe")).to eq(:forbidden_characters)
      expect(refusal("a/b.pdf")).to eq(:forbidden_characters)
      expect(refusal("a\\b.pdf")).to eq(:forbidden_characters)
    end

    it "names the forbidden characters a name holds" do
      expect(described_class.forbidden_characters("a\u202Eb/c\\d")).to eq(["U+202E", "/", "\\"])
      expect(described_class.forbidden_characters("a/b")).to eq(["/"])
      expect(described_class.forbidden_characters("ab")).to eq([])
    end
  end

  describe ".normalize" do
    def normalize(name) = described_class.normalize(name, fallback: "upload-medical")

    it "keeps an ordinary name and the white space inside" do
      expect(normalize("Mein Vertrag  2026.pdf")).to eq("Mein Vertrag  2026.pdf")
    end

    it "replaces what Windows does not allow, and % $ ; besides" do
      expect(normalize('a<b>c:d"e|h?i*j%k$l;m.pdf')).to eq("a-b-c-d-e-h-i-j-k-l-m.pdf")
    end

    it "composes decomposed umlauts" do
      expect(normalize("Müller.pdf")).to eq("Müller.pdf")
    end

    it "drops leading white space and trailing white space and dots" do
      expect(normalize("  scan.pdf .. ")).to eq("scan.pdf")
    end

    it "marks the names Windows reserves" do
      expect(normalize("CON.pdf")).to eq("CON_.pdf")
      expect(normalize("lpt1")).to eq("lpt1_")
      expect(normalize("CONFIG.pdf")).to eq("CONFIG.pdf")
    end

    it "answers the fallback for a name with nothing left" do
      expect(normalize("")).to eq("upload-medical")
      expect(normalize(" ... ")).to eq("upload-medical")
    end

    it "answers names ActiveStorage::Filename#sanitized leaves as they are" do
      ["x%y$z;w|v", " lead", "trail  ", "c:d", "<img src=x onerror=alert(1)>.pdf", "CON", "...",
        "a?b*c\"d", "Müller"].each do |name|
        normalized = normalize(name)
        expect(ActiveStorage::Filename.new(normalized).sanitized).to eq(normalized), name.inspect
      end
    end
  end

  describe ".problem" do
    it "accepts a normalized name of at most 255 bytes and nothing else" do
      expect(described_class.problem("#{"a" * 251}.pdf")).to be_nil
      expect(described_class.problem("#{"a" * 252}.pdf")).to eq(:too_long)
      expect(described_class.problem("a:b.pdf")).to eq(:not_normalized)
      expect(described_class.problem("a\u0000.pdf")).to eq(:control_character)
    end
  end

  describe ".fallback_for" do
    it "names the keys as the file system name does" do
      expect(described_class.fallback_for(key: "medical")).to eq("upload-medical")
      expect(described_class.fallback_for(key: "deregistration", key_number: 2, secondary_key: "signed_form",
        secondary_key_number: 3)).to eq("upload-deregistration-2-signed_form-3")
      expect(described_class.fallback_for(key: "letter", secondary_key: "copy")).to eq("upload-letter-copy")
      expect(described_class.fallback_for(key: nil)).to eq("upload")
    end
  end

  describe ".display" do
    it "shows only safe characters as they are, the rest as codes, shortened" do
      expect(described_class.display("Scan (1).pdf")).to eq("Scan (1).pdf")
      expect(described_class.display("<a href=x>.pdf")).to eq("\\u{3C}a href\\u{3D}x\\u{3E}.pdf")
      expect(described_class.display("r\u202Efdp\u0000.exe")).to eq("r\\u{202E}fdp\\u{0}.exe")
      expect(described_class.display("bad\xFF".b)).to eq("bad\\xFF")
      expect(described_class.display("a" * 100)).to eq("#{"a" * 60}…")
    end
  end
end
