# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# What a SEPA message may carry: ASCII from the basic character set, and a "?"
# for everything else. The German replacements run before the unidecoder, which
# would otherwise drop the diaeresis instead of spelling it out.
describe Wsjrdp2027::SepaText do
  # The module requires stringex/unidecoder alone. The full gem also loads
  # acts_as_url, which gives ActiveRecord::Base a public `included`; every
  # model with `scope :included` (the core's Subscription) then fails to load.
  describe "loading stringex" do
    it "does not pull acts_as_url in" do
      described_class
      expect(defined?(Stringex::ActsAsUrl)).to be_nil
    end

    it "leaves ActiveRecord::Base without a public included" do
      described_class
      expect(ActiveRecord::Base.respond_to?(:included)).to be(false)
    end
  end

  describe ".transliterate" do
    it "spells the German umlauts and the sharp s out" do
      expect(described_class.transliterate("Ärger Straße Größe"))
        .to eq("Aerger Strasse Groesse")
    end

    it "folds the accented latin letters onto their base letters" do
      expect(described_class.transliterate("café François Łódź Ærø Çelik Ğökçe"))
        .to eq("cafe Francois Lodz AEro Celik Goekce")
    end

    it "folds the Romanian comma-below letters" do
      expect(described_class.transliterate("Ștefan Țepeș")).to eq("Stefan Tepes")
    end

    # The punctuation the unidecoder produces is not automatically allowed: the
    # en dash becomes "--" and the ellipsis "...", both fine, while the German
    # quotes become ",," and '"' -- of which only the comma is in the set. The
    # percent sign has no ASCII spelling at all and stays a "?".
    it "replaces every character outside the SEPA set with a question mark" do
      expect(described_class.transliterate("Abm. YP 858 – „Ticket“ … 400 € 50 %"))
        .to eq("Abm. YP 858 -- ,,Ticket? ... 400 EU 50 ?")
    end

    it "transcribes cyrillic and greek" do
      expect(described_class.transliterate("Иван / Νίκος")).to eq("Ivan / Nikos")
    end

    it "keeps the allowed punctuation and drops the rest" do
      expect(described_class.transliterate("a/b-c?d:e(f).g,h'i+j k_l@m&n#o*p"))
        .to eq("a/b-c?d:e(f).g,h'i+j k?l?m?n?o?p")
    end

    it "reads nil as an empty string" do
      expect(described_class.transliterate(nil)).to eq("")
    end

    it "does not truncate" do
      expect(described_class.transliterate("x" * 200).length).to eq(200)
    end
  end

  describe ".limit" do
    it "cuts to the given length" do
      expect(described_class.limit("x" * 200, 140).length).to eq(140)
    end

    it "transliterates before cutting" do
      expect(described_class.limit("Größe", 3)).to eq("Gro")
    end
  end
end
