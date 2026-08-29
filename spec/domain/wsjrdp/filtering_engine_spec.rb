# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Deliberately standalone (no rails spec_helper): the CNF filter ENGINE --
# vocabulary, value objects, schema definition/derivation, the URL codec and the
# catalog projection -- is pure Ruby over activesupport + rison and needs neither
# the app nor a database. Binding a schema only needs something that answers
# `arel_table` with a column lookup, so a Hash-backed fake stands in for the
# relation. The Arel COMPILER and the real bookings schema are covered by
# spec/domain/fin/datev_bookings_filter_schema_spec.rb, which boots Rails.
require "active_support"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/enumerable"
require "bigdecimal"
require "date"
require "json"
require "rison"

module Wsjrdp; end
%w[filtering filtering/operator filtering/type filtering/types filtering/attribute
  filtering/bound_schema filtering/schema filtering/query filtering/url_codec
  filtering/options filtering/slot_equality]
  .each { |file| require_relative "../../../app/domain/wsjrdp/#{file}" }

describe Wsjrdp::Filtering do
  # A relation stand-in: `arel_table[column]` yields a placeholder per column,
  # which is all Attribute#resolved_against needs. Lambda columns get the same
  # table and may return arrays, exactly like the real schemas.
  let(:base) { Struct.new(:arel_table).new(Hash.new { |_h, column| "col:#{column}" }) }

  let(:template) do
    Wsjrdp::Filtering::Schema.define do |s|
      # Accepts six operators, offers three in the editor (accepted vs. pickable).
      s.attribute key: :amount, short_key: :amt, label: "Betrag",
        type: Wsjrdp::Filtering::Types::DECIMAL, operators: %i[gt gte lt between present blank],
        pickable: %i[gte between], operand_min: 0, column: :base_amount
      s.attribute key: :cost_center, short_key: :cc, label: "Kostenstelle",
        type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in present blank],
        column: :cost_center_number
      s.attribute key: :text, short_key: :q, label: "Text",
        type: Wsjrdp::Filtering::Types::TEXT, operators: %i[contains eq regex],
        column: ->(t) { [t[:posting_text], t[:original_posting_text]] }
      s.attribute key: :status, label: "Status", catalog: false,
        type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in], column: :status
    end
  end
  let(:schema) { template.bind(base) }

  it "has a globally unique operator vocabulary" do
    vocabulary = Wsjrdp::Filtering::OPERATOR_VOCABULARY
    expect(vocabulary.values.uniq.size).to eq(vocabulary.size)
    expect(vocabulary.keys.uniq.size).to eq(vocabulary.size)
  end

  # gt sits next to gte/lt on the decimal type: "strictly greater than", which
  # is what a "has bookings" / "has a balance" filter is made of.
  it "offers a strict > next to >= and <, with its own wire key" do
    expect(Wsjrdp::Filtering::OPERATOR_VOCABULARY[:gt]).to eq(:gt)
    operator = Wsjrdp::Filtering::Types::DECIMAL.operator(:gt)
    expect([operator.label, operator.arity]).to eq([">", :one])
    expect(schema.find(:amount).operator(:gt)).to be_present
  end

  # ≤ completes the pair with ≥ on both comparable types; the date label is
  # "bis" (inclusive), next to the exclusive "vor".
  it "offers an inclusive ≤ on decimal and date" do
    expect(Wsjrdp::Filtering::OPERATOR_VOCABULARY[:lte]).to eq(:le)
    expect(Wsjrdp::Filtering::Types::DECIMAL.operator(:lte).label).to eq("≤")
    expect(Wsjrdp::Filtering::Types::DATE.operator(:lte).label).to eq("bis")
    expect(Wsjrdp::Filtering::Types::DECIMAL.operator(:lte).arity).to eq(:one)
  end

  # The comparison labels differ per type: on a decimal the whole set reads as
  # symbols ("=", "≥"), while text keeps the worded "ist genau".
  it "labels the decimal eq as = and the text eq as ist genau" do
    expect(Wsjrdp::Filtering::Types::DECIMAL.operator(:eq).label).to eq("=")
    expect(Wsjrdp::Filtering::Types::TEXT.operator(:eq).label).to eq("ist genau")
  end

  # Glob is a text pattern operator like regex: `*` / `?` are the only
  # wildcards, it comes as a case-insensitive/-sensitive pair, and it carries an
  # operator `hint` the editor shows next to the input.
  it "offers a glob pair on text, with its own wire keys and an editor hint" do
    vocabulary = Wsjrdp::Filtering::OPERATOR_VOCABULARY
    expect([vocabulary[:glob], vocabulary[:glob_cs]]).to eq(%i[gl glc])
    glob = Wsjrdp::Filtering::Types::TEXT.operator(:glob)
    glob_cs = Wsjrdp::Filtering::Types::TEXT.operator(:glob_cs)
    expect([glob.label, glob.arity, glob.case_group, glob.case_sensitive])
      .to eq(["Glob", :one, :glob, false])
    expect([glob_cs.label, glob_cs.case_group, glob_cs.case_sensitive])
      .to eq(["Glob (Groß/Klein)", :glob, true])
    expect(glob.hint).to eq(glob_cs.hint).and include("*").and include("?")
    expect(glob.as_json[:hint]).to eq(glob.hint)
    expect { Wsjrdp::Filtering::Types::DECIMAL.operator(:glob) }.to raise_error(KeyError)
  end

  # ≠ 0 is operand-less: the "has a balance at all" atom of a signed amount.
  it "offers an operand-less ≠ 0 on decimal only" do
    expect(Wsjrdp::Filtering::OPERATOR_VOCABULARY[:nonzero]).to eq(:nz)
    operator = Wsjrdp::Filtering::Types::DECIMAL.operator(:nonzero)
    expect([operator.label, operator.arity]).to eq(["≠ 0", :none])
    expect(operator.arity_satisfied?([])).to be true
    expect { Wsjrdp::Filtering::Types::DATE.operator(:nonzero) }.to raise_error(KeyError)
  end

  describe Wsjrdp::Filtering::Query do
    it "parses a positional tree into slots and conditions and round-trips" do
      tree = [[["amount", "between", 100, 200]], [["cost_center", "in", "3150"], ["cost_center", "blank"]]]
      query = described_class.parse(tree)
      expect(query.slots.size).to eq(2)
      expect(query.slots.last.conditions.map(&:operator)).to eq(%i[in blank])
      expect(query.condition_count).to eq(3)
      expect(query.as_json).to eq(tree)
    end

    it "skips malformed conditions and is empty when nothing survives" do
      query = described_class.parse([["not-an-array"], [[nil, "in", 1]], [["amount"]]])
      expect(query).to be_empty
      expect(described_class.empty).to be_empty
    end
  end

  describe Wsjrdp::Filtering::UrlCodec do
    let(:tree) { [[["amount", "between", 100, 200]], [["cost_center", "in", "3150"], ["cost_center", "blank"]]] }
    let(:query) { Wsjrdp::Filtering::Query.parse(tree) }

    it "encodes with short keys and round-trips" do
      rison = described_class.encode(query, schema: schema)
      expect(rison).to eq("!(!(!(amt,bt,100,200)),!(!(cc,in,'3150'),!(cc,bl)))")
      expect(described_class.decode(rison, schema: schema).as_json).to eq(query.as_json)
    end

    it "accepts full keys and canonicalizes to them" do
      decoded = described_class.decode("!(!(!(amount,between,1,2)))", schema: schema)
      expect(decoded.as_json).to eq([[["amount", "between", 1, 2]]])
    end

    it "drops unknown attributes/operators and survives garbage" do
      decoded = described_class.decode("!(!(!(nope,in,x),!(amt,ge,5)))", schema: schema)
      expect(decoded.as_json).to eq([[["amount", "gte", 5]]])
      expect(described_class.decode("!!!garbage", schema: schema)).to be_empty
      expect(described_class.decode(nil, schema: schema)).to be_empty
    end

    it "drops an operator the attribute does not offer" do
      decoded = described_class.decode("!(!(!(cc,ge,5),!(amt,in,5)))", schema: schema)
      expect(decoded).to be_empty
    end

    it "encodes nothing when no condition survives canonicalization" do
      query = Wsjrdp::Filtering::Query.parse([[["nope", "in", "x"]]])
      expect(described_class.encode(query, schema: schema)).to be_nil
    end

    it "escapes only URL-breaking characters" do
      expect(described_class.escape_for_query("!(a b&c+d%e#f)"))
        .to eq("!(a%20b%26c%2Bd%25e%23f)")
    end
  end

  describe Wsjrdp::Filtering::Schema do
    it "binds columns against the base table, symbols and lambdas alike" do
      expect(schema.find(:amount).column).to eq("col:base_amount")
      expect(schema.find(:text).column).to eq(["col:posting_text", "col:original_posting_text"])
    end

    it "derives without touching the parent and narrows operators" do
      derived = template.derive do |s|
        s.remove(:amount)
        s.operators(:cost_center, %i[in])
      end
      bound = derived.bind(base)
      expect(bound.find(:amount)).to be_nil
      expect(bound.find(:cost_center).operators.map(&:key)).to eq([:in])
      expect(schema.find(:amount)).to be_present
      expect(schema.find(:cost_center).operators.map(&:key)).to eq(%i[in not_in present blank])
    end

    it "binds a subset with only: / except:" do
      expect(template.bind(base, only: %i[amount]).attributes.keys).to eq([:amount])
      expect(template.bind(base, except: %i[amount]).attributes.keys).to eq(%i[cost_center text status])
    end

    it "rejects duplicate short_keys and unknown operator keys" do
      expect {
        described_class.define do |s|
          s.attribute key: :a, short_key: :x, label: "A", type: Wsjrdp::Filtering::Types::TEXT,
            operators: %i[contains], column: :posting_text
          s.attribute key: :b, short_key: :x, label: "B", type: Wsjrdp::Filtering::Types::TEXT,
            operators: %i[contains], column: :posting_text
        end
      }.to raise_error(ArgumentError, /short_key/)
      expect {
        described_class.define do |s|
          s.attribute key: :a, label: "A", type: Wsjrdp::Filtering::Types::TEXT,
            operators: %i[nope], column: :posting_text
        end
      }.to raise_error(KeyError)
    end
  end

  # An attribute ACCEPTS every operator in `operators:` -- that is what the URL
  # codec, fixed slots, presets and the compiler go by -- and OFFERS the
  # `pickable:` subset in the editor's dropdown. Everything but the dropdown is
  # deliberately blind to the distinction.
  describe "accepted vs. pickable operators" do
    it "offers every accepted operator when nothing is declared pickable" do
      cost_center = schema.find(:cost_center)
      expect(cost_center.pickable_operators.map(&:key)).to eq(%i[in not_in present blank])
      expect(cost_center.operators.map(&:key)).to eq(cost_center.pickable_operators.map(&:key))
    end

    it "narrows only the editor's list, in the accepted list's order" do
      amount = schema.find(:amount)
      expect(amount.operators.map(&:key)).to eq(%i[gt gte lt between present blank])
      expect(amount.pickable_operators.map(&:key)).to eq(%i[gte between])
      expect(amount.pickable?(:gte)).to be true
      expect(amount.pickable?(:gt)).to be false
    end

    it "still accepts a non-pickable operator from the wire" do
      decoded = Wsjrdp::Filtering::UrlCodec.decode("!(!(!(amt,gt,5)))", schema: schema)
      expect(decoded.as_json).to eq([[["amount", "gt", 5]]])
      expect(Wsjrdp::Filtering::UrlCodec.encode(decoded, schema: schema))
        .to eq("!(!(!(amt,gt,5)))")
    end

    it "keeps a derived narrowing from widening the editor's list" do
      derived = template.derive { |s| s.operators(:amount, %i[gt gte between]) }
      amount = derived.bind(base).find(:amount)
      expect(amount.operators.map(&:key)).to eq(%i[gt gte between])
      expect(amount.pickable_operators.map(&:key)).to eq(%i[gte between])
    end

    it "raises for a pickable operator the attribute does not accept" do
      expect {
        Wsjrdp::Filtering::Schema.define do |s|
          s.attribute key: :a, label: "A", type: Wsjrdp::Filtering::Types::DECIMAL,
            operators: %i[gte], pickable: %i[gte lte], column: :base_amount
        end
      }.to raise_error(ArgumentError, /pickable operator\(s\) \[:lte\]/)
    end
  end

  # An amount and its magnitude are one variant group whose two members carry
  # `sign:`. The metadata is what the editor renders as the ± / |x| toggle
  # instead of the sub-variant dropdown, so it has to survive binding and
  # narrowing and reach the catalog.
  describe "the sign pair of an amount" do
    def pair_template(first_sign, second_sign, group: "Betrag")
      Wsjrdp::Filtering::Schema.define do |s|
        s.attribute key: :amount_signed, short_key: :amt, label: "Betrag",
          variant_group: group, sign: first_sign, type: Wsjrdp::Filtering::Types::DECIMAL,
          operators: %i[between gte lt], column: :base_amount
        s.attribute key: :amount_abs, short_key: :amta, label: "|Betrag|",
          variant_group: group, sign: second_sign, type: Wsjrdp::Filtering::Types::DECIMAL,
          operators: %i[between gte lt], operand_min: 0, column: :base_amount
      end
    end

    let(:pair) { pair_template(:signed, :absolute) }

    it "carries the sign into the catalog, next to the variant group" do
      catalog = pair.bind(base).catalog[:attributes]
      expect(catalog.pluck(:sign)).to eq(%i[signed absolute])
      expect(catalog.pluck(:variant_group)).to eq(%w[Betrag Betrag])
      expect(catalog.to_json).to include('"sign":"signed"').and include('"sign":"absolute"')
    end

    it "keeps it through binding and through a derived operator narrowing" do
      narrowed = pair.derive { |s| s.operators(:amount_abs, %i[gte]) }.bind(base)
      expect(narrowed.find(:amount_abs).sign).to eq(:absolute)
      expect(narrowed.find(:amount_abs).operators.map(&:key)).to eq(%i[gte])
      expect(narrowed.find(:amount_signed).sign).to eq(:signed)
    end

    it "leaves an attribute that declares none at nil" do
      expect(schema.find(:amount).sign).to be_nil
      expect(schema.catalog[:attributes].first[:sign]).to be_nil
    end

    # Host-authored like the operator lists: a half-declared pair is a typo,
    # not a variant the editor could render, so it fails at declaration time.
    it "raises for a lone sign and for two members of the same kind" do
      expect { pair_template(:signed, nil) }
        .to raise_error(ArgumentError, /variant group "Betrag": sign must be declared/)
      expect { pair_template(:absolute, :absolute) }
        .to raise_error(ArgumentError, /one :signed and one :absolute/)
    end

    it "raises for a sign on a group of one" do
      expect {
        Wsjrdp::Filtering::Schema.define do |s|
          s.attribute key: :amount_abs, label: "|Betrag|", variant_group: "Betrag",
            sign: :absolute, type: Wsjrdp::Filtering::Types::DECIMAL,
            operators: %i[gte], column: :base_amount
        end
      }.to raise_error(ArgumentError, /variant group "Betrag"/)
    end

    # The text searches: a variant group without any sign stays a dropdown and
    # passes untouched, however many members it has.
    it "passes a variant group that declares no sign at all" do
      expect(pair_template(nil, nil).bind(base).attributes.values.map(&:sign)).to eq([nil, nil])
    end

    # The pairing as SlotEquality wants it: {signed key => absolute key}, with
    # String keys, because a condition's attribute is a String there.
    describe "#sign_aliases" do
      it "maps the signed member of every pair onto its magnitude" do
        expect(pair.sign_aliases).to eq("amount_signed" => "amount_abs")
        expect(pair.bind(base).sign_aliases).to eq("amount_signed" => "amount_abs")
      end

      it "is empty without any sign pair" do
        expect(template.sign_aliases).to eq({})
        expect(schema.sign_aliases).to eq({})
        expect(pair_template(nil, nil).sign_aliases).to eq({})
      end

      # A binding that keeps only one member of the pair has nothing to alias:
      # the remaining attribute stands for itself.
      it "drops a pair whose twin the binding leaves behind" do
        expect(pair.bind(base, except: %i[amount_abs]).sign_aliases).to eq({})
        expect(pair.bind(base, only: %i[amount_signed]).sign_aliases).to eq({})
      end
    end
  end

  # THE equality of two CNF slots -- what a preset is recognised by. The set
  # rule itself (order, repetition, an OR-widened slot) is covered where it is
  # used, in spec/domain/wsjrdp/table_state_spec.rb; here: the sign-pair
  # aliasing, which is what `aliases:` adds.
  describe Wsjrdp::Filtering::SlotEquality do
    let(:aliases) { {"booking_balance" => "booking_balance_abs"} }

    def signed(*rest) = [["booking_balance", *rest]]

    def absolute(*rest) = [["booking_balance_abs", *rest]]

    # ≠ 0, hat Wert, ist leer and = 0 ask nothing about the sign, so the
    # magnitude and its signed twin select the same rows.
    it "reads a sign-invariant condition on either member as one" do
      %w[nonzero present blank].each do |operator|
        expect(described_class.same_slot?(signed(operator), absolute(operator), aliases: aliases))
          .to be(true)
      end
      expect(described_class.same_slot?(signed("eq", 0), absolute("eq", 0), aliases: aliases))
        .to be(true)
    end

    # Which operand counts as zero is decided NUMERICALLY, so every spelling of
    # it makes `eq` sign-invariant. The operands themselves keep being compared
    # as they always were (canonically, by their string form), so `= 0` and
    # `= 0.0` stay two conditions -- on both members alike.
    it "recognises the zero operand numerically, however it is written" do
      ["0", 0, 0.0, "0.0", "-0", "-0.00", BigDecimal(0)].each do |zero|
        expect(described_class.same_slot?(signed("eq", zero), absolute("eq", zero),
          aliases: aliases)).to be(true)
      end
      expect(described_class.same_slot?(signed("eq", "0"), absolute("eq", 0), aliases: aliases))
        .to be(true)
    end

    it "leaves an operand it cannot read as a number alone" do
      ["", " ", "null", nil].each do |operand|
        expect(described_class.same_slot?(signed("eq", operand), absolute("eq", operand),
          aliases: aliases)).to be(false)
      end
    end

    # A comparison IS about the sign: |Saldo| ≥ 100 and Saldo ≥ 100 are two
    # different questions, and so are = 5 and = -5.
    it "keeps a comparison member-specific" do
      expect(described_class.same_slot?(signed("gte", 100), absolute("gte", 100), aliases: aliases))
        .to be(false)
      expect(described_class.same_slot?(signed("eq", 5), absolute("eq", 5), aliases: aliases))
        .to be(false)
      expect(described_class.same_slot?(signed("between", 0, 5), absolute("between", 0, 5),
        aliases: aliases)).to be(false)
    end

    it "leaves every attribute standing for itself without aliases" do
      expect(described_class.same_slot?(signed("nonzero"), absolute("nonzero"))).to be(false)
      expect(described_class.same_slot?(signed("eq", 0), absolute("eq", 0))).to be(false)
      expect(described_class.same_slot?(signed("nonzero"), signed("nonzero"))).to be(true)
    end

    it "aliases in one direction only, onto the magnitude" do
      expect(described_class.condition_key(["booking_balance", "nonzero"], aliases: aliases))
        .to eq(described_class.condition_key(["booking_balance_abs", "nonzero"]))
    end

    # The three list operations the presets are made of see the twin as well.
    it "includes, removes and misses a slot through its twin" do
      user = [absolute("nonzero"), [["booking_count", "gt", 0]]]
      twin = [signed("nonzero"), [["booking_count", "gt", 0]]]

      expect(described_class.include_slot?(twin, absolute("nonzero"), aliases: aliases)).to be(true)
      expect(described_class.remove_slots(twin, [absolute("nonzero")], aliases: aliases))
        .to eq([[["booking_count", "gt", 0]]])
      expect(described_class.missing_slots(twin, [absolute("nonzero")], aliases: aliases)).to eq([])
      expect(described_class.missing_slots(user, [signed("gte", 100)], aliases: aliases))
        .to eq([signed("gte", 100)])
    end
  end

  describe "catalog" do
    it "projects only catalog attributes, without SQL or short_keys" do
      catalog = schema.catalog
      keys = catalog[:attributes].pluck(:key)
      expect(keys).to eq(%i[amount cost_center text])
      expect(catalog.to_json).not_to include("short_key")
      expect(catalog.to_json).not_to include("column")
      expect(catalog[:attributes].first[:operators].pluck(:key)).to eq(%i[gt gte lt between present blank])
    end

    # The UI needs both halves: every accepted operator (so a chip can label a
    # condition it may not offer) and a flag saying which are pickable.
    it "ships every accepted operator, flagged pickable or not, plus operand_min" do
      amount = schema.catalog[:attributes].first
      expect(amount[:operand_min]).to eq(0)
      expect(amount[:operators].to_h { |o| [o[:key], o[:pickable]] })
        .to eq(gt: false, gte: true, lt: false, between: true, present: false, blank: false)
      expect(schema.catalog[:attributes][1][:operators].pluck(:pickable)).to all(be true)
    end
  end
end
