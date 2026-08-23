# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Deliberately standalone (no rails spec_helper): RelaxedUrlQuery is pure, the
# spec needs neither the app nor a database -- and the full test boot must never
# be pointed at a shared dev DB by accident. Runs against any bundle that has
# activesupport + rack + rspec, e.g. from the core app directory:
#
#   bundle exec rspec ../hitobito_wsjrdp_2027/spec/models/relaxed_url_query_spec.rb
require "active_support"
require "active_support/core_ext/object/to_query"
require "rack/utils"
require_relative "../../app/models/relaxed_url_query"

# Round-trip safety of the relaxed query encoding (doc/url_encoding.md §6):
# every value -- including raw "%", the literal text "%2C"/"%7E", separators and
# non-ASCII -- must come back byte-identical through Rack's parser, while "," and
# "~" stay literal (readable) in the produced query string.
describe RelaxedUrlQuery do
  def roundtrip(params)
    Rack::Utils.parse_nested_query(RelaxedUrlQuery.to_query(params))
  end

  # What Rack hands the app back for `params`: string keys/values.
  def stringified(params)
    params.to_h { |k, v| [k.to_s, v.is_a?(Array) ? v.map(&:to_s) : v.to_s] }
  end

  describe "readability (the point of the relaxing)" do
    it "keeps , and ~ literal in values" do
      expect(RelaxedUrlQuery.to_query(sort: "bez,nr~")).to eq("sort=bez,nr~")
    end

    it "keeps , and ~ literal across several params (A-Rison sort + cols)" do
      query = RelaxedUrlQuery.to_query("sort" => "bez~,cnt~", "cols" => "nr,bez,~st,sum,cnt")
      expect(query).to eq("cols=nr,bez,~st,sum,cnt&sort=bez~,cnt~")
      expect(query).not_to include("%2C", "%7E")
    end

    it "returns an empty string for empty params" do
      expect(RelaxedUrlQuery.to_query({})).to eq("")
    end
  end

  describe "round-trip safety (the security property)" do
    [
      {"plain" => "hello"},
      {"comma" => "a,b,c"},
      {"tilde" => "x~y~"},
      {"raw percent" => "100%"},
      {"lone percent" => "%"},
      {"encoded comma as DATA" => "%2C"},          # must survive as the 3-char text
      {"encoded tilde as DATA" => "%7E"},
      {"lowercase escapes as DATA" => "%2c%7e"},
      {"double encoded" => "%252C"},
      {"ampersand" => "a&b=c"},
      {"equals" => "a=b"},
      {"plus" => "1+1=2"},
      {"hash" => "a#frag"},
      {"space" => "a b"},
      {"semicolon" => "a;b"},
      {"question mark" => "a?b"},
      {"all sub-delims" => "!$&'()*+,;="},
      {"gen-delims" => ":/?#[]@"},
      {"non-ascii" => "Zäune, Bäume & Käfer ~ 100%"},
      {"emoji" => "🏕️,~%"},
      {"newline & control" => "a\nb\tc"},
      {"injection attempt" => "x%26evil%3D1"}      # must NOT become a new param
    ].each do |params|
      it "round-trips #{params.keys.first.inspect} => #{params.values.first.inspect}" do
        expect(roundtrip(params)).to eq(params)
      end
    end

    it "round-trips keys containing , ~ % & =" do
      params = {"a,b" => "1", "c~d" => "2", "e%f" => "3", "g&h" => "4", "i=j" => "5"}
      expect(roundtrip(params)).to eq(params)
    end

    it "never splits off a forged parameter from hostile values" do
      parsed = roundtrip("q" => "evil=1&admin=true")
      expect(parsed.keys).to eq(["q"])
      expect(parsed["q"]).to eq("evil=1&admin=true")
    end

    it "round-trips array params" do
      expect(roundtrip("account_number" => ["a,1", "b~2", "100%"]))
        .to eq("account_number" => ["a,1", "b~2", "100%"])
    end

    it "round-trips nested hashes (the suppliers show[...] grid)" do
      params = {"grid" => "1", "show" => {"active_zero" => "1", "deactivated_balance" => "1"}}
      expect(roundtrip(params)).to eq(params)
    end

    it "round-trips non-string scalars as their string form" do
      expect(roundtrip(page: 2, per: "all")).to eq(stringified(page: 2, per: "all"))
    end
  end

  describe "deterministic fuzz (500 adversarial values)" do
    let(:charset) do
      [*"a".."f", *"0".."9", "%", ",", "~", "&", "=", "+", "#", " ", ";",
        "'", "(", ")", "*", "!", "$", "[", "]", "ü", "€", "\\", '"'].freeze
    end

    it "round-trips every fuzzed value byte-identically" do
      rng = Random.new(20_260_823) # fixed seed -> reproducible failures
      500.times do |i|
        value = Array.new(rng.rand(0..24)) { charset[rng.rand(charset.size)] }.join
        expect(roundtrip("v" => value)).to eq({"v" => value}),
          "fuzz ##{i} failed for value #{value.inspect}"
      end
    end
  end

  describe "encapsulation (no raw-string relax API)" do
    it "exposes only to_query -- no public method accepts a pre-built string" do
      expect(RelaxedUrlQuery.singleton_methods(false)).to contain_exactly(:to_query)
    end

    it "only relaxes characters that are provably separator-free" do
      expect(RelaxedUrlQuery.const_get(:RELAXATIONS).values).to all(match(/\A[,~]\z/))
    end

    # The relax pieces must not be reachable from outside: otherwise
    # `str.gsub(RelaxedUrlQuery::RELAXATION_PATTERN, RelaxedUrlQuery::RELAXATIONS)`
    # would be exactly the forbidden raw-string relax, assembled past to_query.
    # (Note: Module#const_get deliberately bypasses privacy -- the scope
    # resolution operator is what enforces it, so that is what we assert.)
    [:RELAXATIONS, :RELAXATION_PATTERN].each do |const|
      it "keeps #{const} private" do
        expect(RelaxedUrlQuery.const_get(const)).not_to be_nil # it exists ...
        # ... but is unreachable from outside. const_get deliberately bypasses
        # privacy, so the scope resolution operator is what we must exercise.
        expect { eval("RelaxedUrlQuery::#{const}", binding, __FILE__, __LINE__) } # standard:disable Security/Eval
          .to raise_error(NameError, /private constant/)
      end
    end

    it "exposes no public constants at all" do
      expect(RelaxedUrlQuery.constants(false)).to be_empty
    end

    # A pre-encoded String must never reach the relax step -- rejected explicitly,
    # not by accident (mirrors the JS helper's TypeError).
    ["sort=bez%2Cnr", "", "%2C"].each do |bad|
      it "raises TypeError for the pre-built string #{bad.inspect}" do
        expect { RelaxedUrlQuery.to_query(bad) }.to raise_error(TypeError, /expects a Hash/)
      end
    end

    it "raises TypeError for nil / arrays / other non-hashes" do
      [nil, ["a", "b"], 42, :sym].each do |bad|
        expect { RelaxedUrlQuery.to_query(bad) }.to raise_error(TypeError, /expects a Hash/)
      end
    end
  end
end
