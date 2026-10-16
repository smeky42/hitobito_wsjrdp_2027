# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "active_support"
require "active_support/core_ext/object/blank"

# Standalone (no Rails boot, no DB): the column description is a pure PORO, and
# keeping its spec standalone means the full test boot can never be pointed at a
# shared database (see AGENTS.md, "Running tests").
module Wsjrdp; end
require_relative "../../../app/domain/wsjrdp/table_state_policy"
require_relative "../../../app/domain/wsjrdp/expandable_table_column"
require_relative "../../../app/domain/wsjrdp/expandable_table_columns"

describe Wsjrdp::ExpandableTableColumns do
  subject(:columns) do
    Wsjrdp::ExpandableTableColumns.define(css_prefix: "tblcol") do |c|
      c.column key: "name", abbr: "nm", label: "Name", width: "10rem",
        sort: "people.name", default: true
      c.column key: "amount", abbr: "amt", label: "Betrag", numeric: true,
        sort: "people.amount_cents", default: true
      c.column key: "note", abbr: "nt", label: "Notiz", condensed_label: "Nt"
    end
  end

  describe ".define" do
    it "keeps the declaration order" do
      expect(columns.keys).to eq(%w[name amount note])
      expect(columns.to_a.map(&:label)).to eq(["Name", "Betrag", "Notiz"])
      expect(columns.size).to eq(3)
    end

    it "derives css_class from the css_prefix" do
      expect(columns.map(&:css_class)).to eq(%w[tblcol-name tblcol-amount tblcol-note])
    end

    it "leaves css_class nil without a css_prefix" do
      plain = described_class.define { |c| c.column key: "a", label: "A" }
      expect(plain.fetch("a").css_class).to be_nil
    end

    it "lets a column override the derived css_class" do
      own = described_class.define(css_prefix: "x") do |c|
        c.column key: "a", label: "A", css_class: "own"
      end
      expect(own.fetch("a").css_class).to eq("own")
    end

    it "defaults abbr to the key" do
      plain = described_class.define { |c| c.column key: "a", label: "A" }
      expect(plain.fetch("a").abbr).to eq("a")
    end
  end

  describe "the three derived views of the description" do
    it "#codec maps key => abbr, in column order" do
      expect(columns.codec).to eq("name" => "nm", "amount" => "amt", "note" => "nt")
      expect(columns.codec).to be_frozen
    end

    it "#default_keys lists only the columns shown by default" do
      expect(columns.default_keys).to eq(%w[name amount])
    end

    it "#sort_expressions lists only the sortable columns" do
      expect(columns.sort_expressions)
        .to eq("name" => "people.name", "amount" => "people.amount_cents")
      expect(columns.sort_expressions).to be_frozen
    end

    it "carries a Proc extractor as the sort of an array-backed table" do
      extractor = ->(row) { row[:number].to_s }
      array_backed = described_class.define do |c|
        c.column key: "number", label: "Nr", sort: extractor
      end
      expect(array_backed.sort_expressions["number"]).to equal(extractor)
    end
  end

  describe "#fetch / #key? / Enumerable" do
    it "#fetch finds a column by its key (String or Symbol)" do
      expect(columns.fetch("name").label).to eq("Name")
      expect(columns.fetch(:note).condensed_label).to eq("Nt")
    end

    it "#fetch raises for an unknown key" do
      expect { columns.fetch("nope") }.to raise_error(KeyError)
    end

    it "#key? answers whether a key is described" do
      expect(columns.key?("amount")).to be true
      expect(columns.key?("nope")).to be false
    end

    it "is Enumerable over the columns" do
      expect(columns.select(&:sortable?).map(&:key)).to eq(%w[name amount])
    end
  end

  describe "validation" do
    it "rejects duplicate keys" do
      expect {
        Wsjrdp::ExpandableTableColumns.define do |c|
          c.column key: "a", abbr: "x", label: "A"
          c.column key: "a", abbr: "y", label: "B"
        end
      }.to raise_error(ArgumentError, /duplicate column key\(s\): a/)
    end

    it "rejects duplicate abbreviations" do
      expect {
        Wsjrdp::ExpandableTableColumns.define do |c|
          c.column key: "a", abbr: "x", label: "A"
          c.column key: "b", abbr: "x", label: "B"
        end
      }.to raise_error(ArgumentError, /duplicate column abbreviation\(s\): x/)
    end

    it "rejects a token the sort/cols params could not carry, through the policy's own rule" do
      expect { described_class.define { |c| c.column key: "a", abbr: "a~b", label: "A" } }
        .to raise_error(ArgumentError, /column token "a~b" must match/)
      expect { described_class.define { |c| c.column key: "a,b", label: "A" } }
        .to raise_error(ArgumentError, /column token "a,b" must match/)
    end

    it "holds sort variants to the same rules as columns" do
      expect {
        Wsjrdp::ExpandableTableColumns.define do |c|
          c.column key: "a__x", label: "A"
          c.column key: "a", label: "A", sort_variants: [{name: "x", sort: "1"}]
        end
      }.to raise_error(ArgumentError, /duplicate column key\(s\): a__x/)
      expect { described_class.define { |c| c.column key: "a", label: "A", sort_variants: [{name: "x~", sort: "1"}] } }
        .to raise_error(ArgumentError, /column token "a__x~" must match/)
      expect { described_class.define { |c| c.column key: "a", label: "A", sort_first: "up" } }
        .to raise_error(ArgumentError, /sort direction "up"/)
    end

    it "is the very rule Wsjrdp::TableStatePolicy applies to a codec" do
      expect { Wsjrdp::TableStatePolicy.new(prefix: "", columns: {"a" => "a~b"}) }
        .to raise_error(ArgumentError, /column token "a~b" must match/)
    end
  end

  describe Wsjrdp::ExpandableTableColumn do
    it "#to_table_column builds the widget's column Hash, with the cell" do
      cell = ->(row) { row }
      expect(columns.fetch("amount").to_table_column(cell: cell)).to eq(
        key: "amount", abbr: "amt", label: "Betrag", condensed_label: nil,
        header_label: nil, header_tooltip: nil, group: nil, grow: 0, tabular_nums: true, merge: nil, merge_share: 1,
        target_width: nil, target_grow: 0, truncate: false, sticky: false,
        merge_layouts: nil, header_align: nil, merged_cell: nil,
        numeric: true, width: nil, mobile: true, narrow: true, pinned: nil, visibility: :toggle,
        visibility_default: nil, fallback: nil, css_class: "tblcol-amount",
        sort_key: "amount", sort_first: "asc", sort_variants: [], cell: cell
      )
    end

    describe "pinned and visibility" do
      it "takes :start or :end, :toggle or :tristate with a default of three" do
        col = Wsjrdp::ExpandableTableColumn.new(key: "x", pinned: :end, visibility: :tristate, default: :auto)
        expect([col.pinned, col.visibility, col.default, col.default?]).to eq([:end, :tristate, :auto, true])
        expect(Wsjrdp::ExpandableTableColumn.new(key: "x", visibility: :tristate, default: false).default?).to be false
        expect(Wsjrdp::ExpandableTableColumn.new(key: "x", visibility: :tristate, default: true).default).to eq(:always)
      end

      it "refuses what does not fit" do
        expect { Wsjrdp::ExpandableTableColumn.new(key: "x", pinned: :middle) }.to raise_error(ArgumentError, /pinned/)
        expect { Wsjrdp::ExpandableTableColumn.new(key: "x", visibility: :tristate, default: :maybe) }
          .to raise_error(ArgumentError, /tristate default/)
        expect { Wsjrdp::ExpandableTableColumn.new(key: "x", pinned: :start, merge: "m") }
          .to raise_error(ArgumentError, /merge or group/)
      end
    end

    describe "sort variants" do
      let(:measures) do
        Wsjrdp::ExpandableTableColumns.define do |c|
          c.column key: "number", abbr: "nr", label: "Nr", sort: "number"
          c.column key: "total", abbr: "tot", label: "Gesamt", sort_first: "desc",
            sort_variants: [{name: "ist", label: "ist", title: "IST", sort: "actual"},
              {name: "pct", label: "%", title: "Ausschöpfung", sort: "share", first: "asc"}]
        end
      end

      it "are sort keys of their own, outside the columns" do
        expect(measures.keys).to eq(%w[number total])
        expect(measures.codec).to eq("number" => "nr", "total" => "tot")
        expect(measures.sort_variant_codec).to eq(
          "total__ist" => ["tot_ist", "total"], "total__pct" => ["tot_pct", "total"]
        )
        expect(measures.sort_expressions).to eq(
          "number" => "number", "total__ist" => "actual", "total__pct" => "share"
        )
      end

      it "are the header's chips, with the column's first direction unless they name one" do
        expect(measures.fetch("total").to_table_column(cell: nil)).to include(
          sort_key: nil, sort_first: "desc",
          sort_variants: [{key: "total__ist", label: "ist", title: "IST", first: "desc"},
            {key: "total__pct", label: "%", title: "Ausschöpfung", first: "asc"}]
        )
      end

      it "reach a policy given the whole collection" do
        policy = Wsjrdp::TableStatePolicy.new(prefix: "", columns: measures)
        expect(policy.column_keys).to eq(%w[number total])
        expect(policy.sort_key_for("tot_pct")).to eq("total__pct")
        expect(policy.sort_key_for("total__ist")).to eq("total__ist")
        expect(policy.sort_key_for("nr")).to eq("number")
        expect(policy.sort_key_for("tot")).to eq("total")
        expect(policy.sort_column_for("total__pct")).to eq("total")
        expect(policy.abbr_for("total__pct")).to eq("tot_pct")
      end
    end

    it "leaves sort_key nil for a column that cannot be sorted" do
      expect(columns.fetch("note").to_table_column(cell: ->(r) { r })[:sort_key]).to be_nil
    end

    it "is frozen and compares by value" do
      expect(columns.fetch("note")).to be_frozen
      expect(described_class.new(key: "a", label: "A"))
        .to eq(described_class.new(key: "a", label: "A"))
    end
  end
end

describe Wsjrdp::ExpandableTableColumn do
  def column(**options) = described_class.new(key: "name", label: "Name", **options)

  describe "widths" do
    it "keeps the old defaults: no target, no truncation, not sticky" do
      expect(column(width: "8rem").to_table_column(cell: nil))
        .to include(target_width: nil, target_grow: 0, truncate: false, sticky: false, grow: 0)
    end

    it "gives a target wider than the width a target_grow of 1" do
      expect(column(width: "8rem", target_width: "13rem")).to have_attributes(target_width: "13rem", target_grow: 1)
    end

    it "keeps a given target_grow" do
      expect(column(width: "8rem", target_width: "13rem", target_grow: 2.5).target_grow).to eq(2.5)
    end

    it "gives a target as wide as the width no target_grow" do
      expect(column(width: "8rem", target_width: "8rem").target_grow).to eq(0)
    end

    it "refuses a target_grow of 0 or less" do
      expect { column(width: "8rem", target_width: "13rem", target_grow: 0) }.to raise_error(ArgumentError, /above 0/)
      expect { column(width: "8rem", target_width: "13rem", target_grow: -1) }.to raise_error(ArgumentError, /above 0/)
    end

    it "refuses a target_grow without a target_width" do
      expect { column(width: "8rem", target_grow: 1) }.to raise_error(ArgumentError, /needs a target_width/)
    end

    it "refuses a target narrower than the width" do
      expect { column(width: "8rem", target_width: "7rem") }.to raise_error(ArgumentError, /narrower/)
    end

    it "refuses widths that are not rem" do
      expect { column(width: "100px", target_width: "13rem") }.to raise_error(ArgumentError, /must be rem/)
      expect { column(target_width: "13rem") }.to raise_error(ArgumentError, /must be rem/)
    end

    it "takes a target on a merged column" do
      expect(column(width: "8rem", target_width: "13rem", merge: "name"))
        .to have_attributes(target_width: "13rem", target_grow: 1, merge: "name")
    end

    it "takes truncate and sticky as booleans" do
      expect(column(width: "8rem", truncate: 1, sticky: "yes")).to have_attributes(truncate: true, sticky: true)
    end

    it "refuses a sticky column without a rem width, merged, grouped or hidden on a phone" do
      expect { column(sticky: true) }.to raise_error(ArgumentError, /width in rem/)
      expect { column(width: "8rem", sticky: true, merge: "x") }.to raise_error(ArgumentError, /merge/)
      expect { column(width: "8rem", sticky: true, group: "G") }.to raise_error(ArgumentError, /group/)
      expect { column(width: "8rem", sticky: true, mobile: false) }.to raise_error(ArgumentError, /mobile/)
    end
  end
end
