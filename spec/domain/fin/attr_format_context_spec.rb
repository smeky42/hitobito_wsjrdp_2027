# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Deliberately standalone (no rails spec_helper): Fin::AttrFormatContext and
# Wsjrdp::TableContext are pure POROs, so the spec needs neither the app nor a
# database. Both declare themselves compactly (class Fin::AttrFormatContext),
# which only resolves once the parent constant exists.
module Wsjrdp; end
require_relative "../../../app/domain/wsjrdp/table_context"
module Fin; end
require_relative "../../../app/domain/fin/attr_format_context"

# WHERE a finance value is being shown: the mode the host decided, the table
# situation it may sit in, and the jsonb column a raw block is rendering.
describe Fin::AttrFormatContext do
  describe "the mode" do
    it "accepts the two modes there are" do
      expect(described_class.new(mode: :regular)).to be_regular
      expect(described_class.new(mode: :embedded)).to be_embedded
    end

    it "answers only one of the two per context" do
      ctx = described_class.new(mode: :regular)
      expect(ctx.embedded?).to be(false)
      expect(described_class.new(mode: :embedded).regular?).to be(false)
    end

    it "rejects a mode that is neither" do
      expect { described_class.new(mode: :inline) }
        .to raise_error(ArgumentError, /mode must be one of regular, embedded/)
    end

    it "rejects a missing mode" do
      expect { described_class.new(mode: nil) }.to raise_error(ArgumentError)
    end
  end

  describe "the factories" do
    it "builds the page context without a table" do
      ctx = described_class.regular
      expect(ctx).to be_regular
      expect(ctx.table_context).to be_nil
    end

    it "builds the embedded context around a table context" do
      table_context = Wsjrdp::TableContext.new(level: 1, lazy: true)
      ctx = described_class.embedded(table_context)
      expect(ctx).to be_embedded
      expect(ctx.table_context).to equal(table_context)
    end
  end

  describe "the table situation" do
    it "reads as a page when there is no table context" do
      ctx = described_class.regular
      expect(ctx.level).to eq(0)
      expect(ctx.in_table?).to be(false)
      expect(ctx.lazy?).to be(false)
    end

    # A directly rendered detail: it sits in a table, but nothing was loaded
    # through a frame.
    it "reads level and lazy off the table context" do
      ctx = described_class.embedded(Wsjrdp::TableContext.new(level: 1, lazy: false))
      expect(ctx.level).to eq(1)
      expect(ctx.in_table?).to be(true)
      expect(ctx.lazy?).to be(false)
    end

    it "counts a table inside a detail one deeper" do
      ctx = described_class.embedded(Wsjrdp::TableContext.new(level: 2, lazy: true))
      expect(ctx.level).to eq(2)
      expect(ctx.in_table?).to be(true)
      expect(ctx.lazy?).to be(true)
    end

    # Level 0 IS a table context -- the table of a page -- but not a row's detail.
    it "is not in a table at level 0" do
      ctx = described_class.embedded(Wsjrdp::TableContext.new(level: 0))
      expect(ctx.level).to eq(0)
      expect(ctx.in_table?).to be(false)
    end
  end

  describe "#with_raw_source" do
    let(:table_context) { Wsjrdp::TableContext.new(level: 1, lazy: true) }
    let(:ctx) { described_class.embedded(table_context) }

    it "has no raw source outside a raw block" do
      expect(ctx.raw_source).to be_nil
      expect(described_class.regular.raw_source).to be_nil
    end

    it "names the jsonb column and keeps the rest of the situation" do
      raw_ctx = ctx.with_raw_source(:other_moss_columns)
      expect(raw_ctx.raw_source).to eq(:other_moss_columns)
      expect(raw_ctx.mode).to eq(:embedded)
      expect(raw_ctx.table_context).to equal(table_context)
    end

    it "leaves the context it was asked untouched" do
      ctx.with_raw_source(:other_datev_columns)
      expect(ctx.raw_source).to be_nil
    end

    # Two raw blocks in one partial: the second must not see the first's column.
    it "answers a second block with its own column" do
      first = ctx.with_raw_source(:other_datev_columns)
      expect(first.with_raw_source(:other_moss_columns).raw_source).to eq(:other_moss_columns)
    end
  end
end
