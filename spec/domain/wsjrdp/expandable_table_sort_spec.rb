# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Deliberately standalone (no rails spec_helper): Wsjrdp::ExpandableTableSort is
# pure value logic, the spec needs neither the app nor a database. Runs against
# any bundle that has activesupport + rspec, e.g. from the core app directory:
#
#   bundle exec rspec ../hitobito_wsjrdp_2027/spec/domain/wsjrdp/expandable_table_sort_spec.rb
require "active_support"
require "active_support/core_ext/object/blank"

module Wsjrdp; end
require_relative "../../../app/domain/wsjrdp/expandable_table_sort"

describe Wsjrdp::ExpandableTableSort do
  subject(:sort) { described_class }

  describe ".decode" do
    it "returns [] for nil" do
      expect(sort.decode(nil)).to eq([])
    end

    it "returns [] for an empty string" do
      expect(sort.decode("")).to eq([])
    end

    it "returns [] for whitespace-only" do
      expect(sort.decode("   ")).to eq([])
    end

    it "parses a single asc column" do
      expect(sort.decode("bez")).to eq([["bez", "asc"]])
    end

    it "parses a single desc column" do
      expect(sort.decode("nr~")).to eq([["nr", "desc"]])
    end

    # docstring example: bez,nr~  ==  [["bez", "asc"], ["nr", "desc"]]
    it "parses multiple columns" do
      expect(sort.decode("bez,nr~")).to eq([["bez", "asc"], ["nr", "desc"]])
    end

    it "accepts the wrapped !(…) RISON form" do
      expect(sort.decode("!(bez,nr~)")).to eq([["bez", "asc"], ["nr", "desc"]])
    end

    it "returns [] for empty wrapped form !()" do
      expect(sort.decode("!()")).to eq([])
    end

    it "drops duplicate columns (first wins)" do
      expect(sort.decode("bez,nr,bez~")).to eq([["bez", "asc"], ["nr", "asc"]])
    end

    it "ignores empty tokens from extra commas" do
      expect(sort.decode(",bez,,nr~,")).to eq([["bez", "asc"], ["nr", "desc"]])
    end

    it "ignores a bare ~ (empty symbol)" do
      expect(sort.decode("~,bez")).to eq([["bez", "asc"]])
    end

    it "strips whitespace around tokens" do
      expect(sort.decode(" bez , nr~ ")).to eq([["bez", "asc"], ["nr", "desc"]])
    end
  end

  describe ".encode" do
    it "returns nil for an empty list" do
      expect(sort.encode([])).to be_nil
    end

    it "returns nil for nil" do
      expect(sort.encode(nil)).to be_nil
    end

    it "encodes a single asc column" do
      expect(sort.encode([["bez", "asc"]])).to eq("bez")
    end

    it "encodes a single desc column" do
      expect(sort.encode([["nr", "desc"]])).to eq("nr~")
    end

    it "encodes multiple columns" do
      expect(sort.encode([["bez", "asc"], ["nr", "desc"]])).to eq("bez,nr~")
    end

    it "treats a non-desc dir as asc" do
      expect(sort.encode([["x", "asc"], ["y", nil]])).to eq("x,y")
    end

    it "round-trips through decode" do
      list = [["bez", "asc"], ["nr", "desc"], ["cnt", "asc"]]
      expect(sort.decode(sort.encode(list))).to eq(list)
    end
  end

  describe ".next_dir" do
    it "cycles first direction, opposite direction, not sorted" do
      expect([nil, "asc", "desc"].map { |dir| sort.next_dir(dir, "asc") }).to eq(["asc", "desc", nil])
      expect([nil, "desc", "asc"].map { |dir| sort.next_dir(dir, "desc") }).to eq(["desc", "asc", nil])
    end

    it "starts ascending by default" do
      expect(sort.next_dir(nil)).to eq("asc")
    end
  end

  describe ".after_click" do
    it "sorts by a new key alone, in its first direction" do
      expect(sort.after_click([], "bez")).to eq([["bez", "asc"]])
      expect(sort.after_click([], "sum", first: "desc")).to eq([["sum", "desc"]])
    end

    it "steps the key along its cycle" do
      expect(sort.after_click([["bez", "asc"]], "bez")).to eq([["bez", "desc"]])
      expect(sort.after_click([["bez", "desc"]], "bez")).to eq([])
      expect(sort.after_click([["sum", "desc"]], "sum", first: "desc")).to eq([["sum", "asc"]])
      expect(sort.after_click([["sum", "asc"]], "sum", first: "desc")).to eq([])
    end

    it "replaces every other level" do
      expect(sort.after_click([["bez", "asc"]], "nr")).to eq([["nr", "asc"]])
      expect(sort.after_click([["nr", "asc"], ["bez", "asc"]], "bez")).to eq([["bez", "desc"]])
    end

    it "clears the whole sort when the key steps to not sorted" do
      expect(sort.after_click([["nr", "asc"], ["bez", "desc"]], "bez")).to eq([])
    end

    it "converts token to string" do
      expect(sort.after_click([], :bez)).to eq([["bez", "asc"]])
    end
  end

  describe ".after_shift_click" do
    let(:slot) { ->(key) { key.split("__").first } }

    it "appends a new key as the last level" do
      expect(sort.after_shift_click([["nr", "asc"]], "bez")).to eq([["nr", "asc"], ["bez", "asc"]])
      expect(sort.after_shift_click([], "sum", first: "desc")).to eq([["sum", "desc"]])
    end

    it "steps a key in place" do
      list = [["nr", "asc"], ["bez", "asc"]]
      expect(sort.after_shift_click(list, "nr")).to eq([["nr", "desc"], ["bez", "asc"]])
      expect(sort.after_shift_click(list, "bez")).to eq([["nr", "asc"], ["bez", "desc"]])
    end

    it "drops a key that steps to not sorted, keeping the others" do
      expect(sort.after_shift_click([["nr", "desc"], ["bez", "asc"]], "nr")).to eq([["bez", "asc"]])
    end

    it "lets another variant of the same column take over that level" do
      list = [["nr", "asc"], ["y26__ist", "asc"], ["bez", "asc"]]
      expect(sort.after_shift_click(list, "y26__pct", first: "desc", slot: slot))
        .to eq([["nr", "asc"], ["y26__pct", "desc"], ["bez", "asc"]])
    end

    it "keeps variants of different columns apart" do
      expect(sort.after_shift_click([["y26__ist", "desc"]], "y27__ist", first: "desc", slot: slot))
        .to eq([["y26__ist", "desc"], ["y27__ist", "desc"]])
    end
  end

  describe ".without / .only / .move" do
    let(:list) { [["a", "asc"], ["b", "desc"], ["c", "asc"]] }

    it "removes one level" do
      expect(sort.without(list, 1)).to eq([["a", "asc"], ["c", "asc"]])
    end

    it "keeps only one level" do
      expect(sort.only(list, 2)).to eq([["c", "asc"]])
      expect(sort.only(list, 5)).to eq(list)
    end

    it "moves a level" do
      expect(sort.move(list, 2, 0)).to eq([["c", "asc"], ["a", "asc"], ["b", "desc"]])
      expect(sort.move(list, 0, 1)).to eq([["b", "desc"], ["a", "asc"], ["c", "asc"]])
      expect(sort.move(list, 0, 3)).to eq(list)
    end
  end

  describe ".state" do
    let(:list) { [["bez", "asc"], ["nr", "desc"]] }

    it "returns [dir, rank] for the primary column" do
      expect(sort.state(list, "bez")).to eq(["asc", 1])
    end

    it "returns [dir, rank] for a secondary column" do
      expect(sort.state(list, "nr")).to eq(["desc", 2])
    end

    it "returns [nil, nil] for an absent column" do
      expect(sort.state(list, "cnt")).to eq([nil, nil])
    end

    it "returns [nil, nil] for an empty list" do
      expect(sort.state([], "bez")).to eq([nil, nil])
    end

    it "converts token to string" do
      expect(sort.state(list, :bez)).to eq(["asc", 1])
    end
  end
end
