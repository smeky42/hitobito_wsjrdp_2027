# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp2027::PaymentCode do
  # Written by wsjrdp_scripts (payment_code_test_vectors()); both
  # implementations must reproduce them exactly.
  let(:vectors) do
    JSON.parse(HitobitoWsjrdp2027::Wagon.root.join("spec/fixtures/files/payment_code_vectors.json").read)
  end

  it "reproduces the codewords, codes and printed forms of wsjrdp_scripts" do
    vectors.each do |vector|
      codeword = described_class.encode_codeword(vector["data"])

      expect(codeword).to eq(vector["codeword"]), vector["data"]
      expect(described_class.code_from_codeword(codeword)).to eq(vector["code"]), vector["data"]
      expect(described_class.format_code(vector["code"])).to eq(vector["printed"]), vector["data"]
    end
  end

  it "takes every vector as valid, in either form" do
    vectors.each do |vector|
      expect(described_class.valid?(vector["code"])).to be(true), vector["code"]
      expect(described_class.valid?(vector["printed"].downcase)).to be(true), vector["printed"]
      expect(described_class.valid_codeword?(vector["codeword"])).to be(true), vector["codeword"]
    end
  end

  it "encodes other parity lengths as wsjrdp_scripts does" do
    expect(described_class.encode_codeword("K7M3", parity_length: 2)).to eq("K7M395")
  end

  describe ".valid?" do
    let(:code) { "RF75K7M3QX9PNFK3" }

    it "refuses a wrong symbol, wrong check digits and a wrong length" do
      expect(described_class.valid?("RF75K7M3QX9PNFK4")).to be(false)
      expect(described_class.valid?("RF76K7M3QX9PNFK3")).to be(false)
      expect(described_class.valid?("RF75K7M3QX9PNFK")).to be(false)
      expect(described_class.valid?("XX75K7M3QX9PNFK3")).to be(false)
    end

    it "reads look-alikes, spaces and hyphens" do
      expect(described_class.compact("rf75 k7m3-qx9p nfk3")).to eq(code)
      expect(described_class.compact("RF75K7M3QX9PNFKO")).to eq("RF75K7M3QX9PNFK0")
      expect(described_class.codeword_of("RF75 K7M3 QX9P NFK3")).to eq("K7M3QX9PNFK3")
    end
  end

  describe ".generate_distinct" do
    it "makes a valid code" do
      expect(described_class.valid?(described_class.generate_distinct)).to be(true)
    end

    it "keeps the distances to the issued codes" do
      issued = Array.new(50) { described_class.generate_distinct }
      code = described_class.generate_distinct(issued)
      hamming, levenshtein = described_class.distances(described_class.codeword_of(code),
        issued.map { |c| described_class.codeword_of(c) })

      expect(hamming).to be >= described_class::MIN_HAMMING_DISTANCE
      expect(levenshtein).to be >= described_class::MIN_LEVENSHTEIN_DISTANCE
    end

    it "takes the farthest draw when none is far enough, and never an issued one" do
      draws = %w[00000001 00000002].cycle
      near = described_class.code_from_codeword(described_class.encode_codeword("00000000"))
      code = described_class.generate_distinct([near], max_attempts: 2, random_data: -> { draws.next })

      expect(%w[00000001 00000002]).to include(described_class.codeword_of(code)[0, 8])
      expect { described_class.generate_distinct([near], max_attempts: 2, random_data: -> { "00000000" }) }
        .to raise_error(described_class::Error)
      expect do
        described_class.generate_distinct([near], max_attempts: 1, raise_when_too_close: true,
          random_data: -> { "00000001" })
      end.to raise_error(described_class::Error)
    end

    it "refuses lengths an RF reference cannot hold" do
      expect { described_class.generate_distinct(data_length: 18, parity_length: 4) }.to raise_error(ArgumentError)
    end
  end

  describe Wsjrdp2027::PaymentCode::Index do
    # Comparing with every codeword one by one, the way the index must answer.
    def naive(codeword, issued)
      hamming = levenshtein = codeword.length + 1
      issued.each do |other|
        if other.length == codeword.length
          hamming = [hamming, Wsjrdp2027::PaymentCode.hamming_distance(codeword, other)].min
        end
        levenshtein = [levenshtein, Wsjrdp2027::PaymentCode.levenshtein_distance(codeword, other)].min
      end
      [hamming, levenshtein]
    end

    # A codeword with a few symbols changed, dropped or added: close
    # neighbours, which is where the pruning has to be exact.
    def mutate(codeword, rng)
      chars = codeword.chars
      rng.rand(1..3).times do
        case rng.rand(3)
        when 0 then chars[rng.rand(chars.size)] = described_class::ALPHABET[rng.rand(32)]
        when 1 then chars.delete_at(rng.rand(chars.size))
        else chars.insert(rng.rand(chars.size + 1), described_class::ALPHABET[rng.rand(32)])
        end
      end
      chars.join
    end

    let(:described_class) { Wsjrdp2027::PaymentCode }

    it "answers exactly as comparing one by one" do
      rng = Random.new(2027)
      issued = Array.new(300) { described_class.generate_codeword }
      issued += issued.first(60).map { |codeword| mutate(codeword, rng) }
      index = described_class::Index.new(issued)

      queries = Array.new(100) { described_class.generate_codeword } + issued.sample(60, random: rng).map { |c| mutate(c, rng) }
      queries.each { |query| expect(index.distances(query)).to eq(naive(query, issued)), query }
    end

    it "grows with add" do
      index = described_class::Index.new
      expect(index.distances("K7M3QX9PNFK3")).to eq([13, 13])

      index << "K7M3QX9PNFK3"
      expect(index.distances("K7M3QX9PNFK3")).to eq([0, 0])
      expect(index.size).to eq(1)
    end
  end

  describe "distances" do
    it "counts substitutions, and insertions and deletions in Levenshtein" do
      expect(described_class.hamming_distance("ABCD", "ABCE")).to eq(1)
      expect(described_class.levenshtein_distance("ABCD", "ABD")).to eq(1)
      expect(described_class.levenshtein_distance("ABCD", "BACD")).to eq(2)
    end
  end
end
