# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "active_support"
require "active_support/core_ext/object/blank"

# Standalone (no Rails boot, no DB): the reckoning of target widths is pure.
module Wsjrdp; end
require_relative "../../../app/domain/wsjrdp/table_state_policy"
require_relative "../../../app/domain/wsjrdp/expandable_table_column"
require_relative "../../../app/domain/wsjrdp/expandable_table_layout"

describe Wsjrdp::ExpandableTableLayout do
  def col(key, width, target = nil, target_grow: nil, grow: 0, sticky: false, **rest)
    Wsjrdp::ExpandableTableColumn.new(key: key, label: key, width: width, target_width: target,
      target_grow: target_grow, grow: grow, sticky: sticky, **rest).to_table_column(cell: nil)
  end

  def layout(columns, gap_keys: [], grow_max: "100cqw", gap_max: "0px")
    min_rem = columns.sum { |c| c[:width].to_f }
    described_class.new(columns: columns, min_rem: min_rem, gap_keys: gap_keys, grow_max: grow_max, gap_max: gap_max)
  end

  # The water level, found by bisection: the level c at which the targets
  # take exactly the room (or all of their spans), each min(tg * c, span).
  def water_extras(targets, room_px)
    spans = targets.to_h { |c| [c[:key], (c[:target_width].to_f - c[:width].to_f) * 16] }
    grows = targets.to_h { |c| [c[:key], described_class.target_grow_of(c)] }
    used = ->(level) { spans.sum { |key, span| [grows[key] * level, span].min } }
    low, high = 0.0, 10_000.0
    80.times do
      mid = (low + high) / 2
      (used.call(mid) < room_px) ? low = mid : high = mid
    end
    spans.to_h { |key, span| [key, [grows[key] * low, span].min] }
  end

  describe ".target_column?" do
    it "is true only for a target wider than the width" do
      expect(described_class.target_column?(col("a", "8rem", "13rem"))).to be(true)
      expect(described_class.target_column?(col("a", "8rem", "8rem"))).to be(false)
      expect(described_class.target_column?(col("a", "8rem"))).to be(false)
    end
  end

  describe "#col_width" do
    it "adds the target share, the growth and the gap" do
      columns = [col("a", "8rem", "13rem", grow: 2), col("b", "7rem"), col("c", "5rem", "9rem", target_grow: 0.5)]
      subject = layout(columns, gap_keys: %w[a b])
      expect(subject.col_width(columns[0])).to eq("calc(8rem + min(1 * var(--exp-c1), 5rem) + 2 * var(--exp-c2) + var(--exp-g))")
      expect(subject.col_width(columns[1])).to eq("calc(7rem + var(--exp-g))")
      expect(subject.col_width(columns[2])).to eq("calc(5rem + min(0.5 * var(--exp-c1), 4rem))")
    end

    it "leaves a plain column at its width" do
      columns = [col("a", "8rem", "13rem"), col("b", "7rem")]
      expect(layout(columns).col_width(columns[1])).to eq("7rem")
    end
  end

  describe "#table_style" do
    it "states the water level as the max of its lines, in the order of span / target_grow" do
      columns = [col("a", "8rem", "13rem"), col("b", "7rem", "9rem")]
      style = layout(columns).table_style
      # b (span 2) reaches its target first, then a goes on alone.
      expect(style).to include("--exp-c1: clamp(0px, round(down, max(((100cqw - 15rem) - 0rem) / 2, " \
        "((100cqw - 15rem) - 2rem) / 1), 1px), 5rem)")
      expect(style).to include("--exp-c2: 0px", "--exp-g: 0px", "min-width: 15rem")
      expect(style).to include("width: calc(15rem + var(--exp-t) + 0 * var(--exp-c2) + 0 * var(--exp-g))")
    end

    it "lets the growing columns and the gaps have what the targets leave" do
      columns = [col("a", "8rem", "13rem", grow: 1), col("b", "7rem")]
      style = layout(columns, gap_keys: %w[a], grow_max: "1rem", gap_max: "1.5rem").table_style
      expect(style).to include("--exp-c2: clamp(0px, round(down, ((100cqw - 15rem) - 5rem) / 1, 1px), 1rem)")
      expect(style).to include("--exp-g: clamp(0px, round(down, ((100cqw - 15rem) - var(--exp-t) - 1 * var(--exp-c2)) / 1, 1px), 1.5rem)")
    end
  end

  describe "#max_width_style" do
    it "adds every span, every growth and every gap" do
      columns = [col("a", "8rem", "13rem", grow: 1), col("b", "7rem", "9rem")]
      expect(layout(columns, gap_keys: %w[a], grow_max: "1rem", gap_max: "1.5rem").max_width_style)
        .to eq("max-width: calc(15rem + 7rem + 1 * 1rem + 1 * 1.5rem)")
    end
  end

  describe "#extras_at" do
    let(:columns) do
      [col("person", "8rem", "13rem", grow: 1), col("kind", "7rem", "9rem"),
        col("note", "6rem", "16rem", target_grow: 3), col("id", "5rem")]
    end
    let(:targets) { columns.select { |c| described_class.target_column?(c) } }

    it "widens the targets like the water level, to the pixel" do
      [0, 1, 37, 80, 160, 199, 250, 288, 300, 333, 500].each do |room|
        extras = layout(columns).extras_at(room, grow_max_px: nil, gap_max_px: 0)
        water = water_extras(targets, [room, 272].min)
        targets.each do |c|
          tolerance = described_class.target_grow_of(c)
          expect(extras.fetch(c[:key]) - (c[:grow].to_f * [((room - 272) / 1.0).floor, 0].max))
            .to be_within(tolerance).of(water.fetch(c[:key])), "room #{room}, #{c[:key]}"
        end
      end
    end

    it "never takes more than the room" do
      [0, 13, 100, 271, 272, 273, 1000].each do |room|
        extras = layout(columns, gap_keys: %w[person kind], grow_max: "1rem", gap_max: "1.5rem")
          .extras_at(room, grow_max_px: 16, gap_max_px: 24)
        expect(extras.values.sum).to be <= room
      end
    end

    it "brings every column to its target before any grows past it or any gap grows" do
      subject = layout(columns, gap_keys: %w[person], grow_max: "1rem", gap_max: "1.5rem")
      at_target = subject.extras_at(272, grow_max_px: 16, gap_max_px: 24)
      expect(at_target).to eq("person" => 80, "kind" => 32, "note" => 160, "id" => 0)
      past = subject.extras_at(300, grow_max_px: 16, gap_max_px: 24)
      expect(past).to eq("person" => 80 + 16 + 12, "kind" => 32, "note" => 160, "id" => 0)
    end

    it "stops a column at its target without a grow" do
      extras = layout(columns).extras_at(5000, grow_max_px: nil, gap_max_px: 0)
      expect(extras.slice("kind", "note")).to eq("kind" => 32, "note" => 160)
    end
  end

  describe ".sticky_lefts" do
    let(:width) { ->(c) { c[:width] } }

    it "offsets the leading sticky columns by the widths before them" do
      columns = [col("a", "8rem", sticky: true), col("b", "7rem", sticky: true), col("c", "5rem")]
      expect(described_class.sticky_lefts(columns, width)).to eq("a" => "0px", "b" => "calc(8rem)")
      expect(described_class.sticky_lefts(columns, width, selection: true))
        .to eq("a" => "calc(2rem)", "b" => "calc(2rem + 8rem)")
    end

    it "keeps a sticky column behind a non-sticky one scrolling" do
      columns = [col("a", "8rem"), col("b", "7rem", sticky: true)]
      expect(described_class.sticky_lefts(columns, width)).to eq({})
    end
  end

  describe ".narrow_css" do
    it "collapses the narrow columns below the narrowest width, in the table's own container" do
      css = described_class.narrow_css("dk", min_rem: 35.75, mobile_rem: 0, narrow_rem: 3.5, narrow_phone_rem: 3.5)
      expect(css).to start_with("@container exp-dk (width < 35.75rem) {")
      expect(css).to include('[data-exptbl="dk"] > table { --exp-nn: 3.5rem; }')
      expect(css).to include('[data-exptbl="dk"] > table > * > tr > .exp-no-narrow {')
      expect(css).to include("> .exp-detail > .exp-narrow-only")
      expect(css).not_to include("@media")
    end

    it "reckons on a phone without the columns a phone does without" do
      css = described_class.narrow_css("dk", min_rem: 35.75, mobile_rem: 7.75, narrow_rem: 7.5, narrow_phone_rem: 3.5)
      expect(css).to include("@media (min-width: 768px) { @container exp-dk (width < 35.75rem) " \
        '{ [data-exptbl="dk"] > table { --exp-nn: 7.5rem; }')
      expect(css).to include("@media (max-width: 767.98px) { @container exp-dk (width < 28rem) " \
        '{ [data-exptbl="dk"] > table { --exp-nn: 3.5rem; }')
    end
  end

  describe "#table_style with columns a narrow table does without" do
    it "takes their widths out of the narrowest width" do
      style = described_class.new(columns: [col("a", "8rem", "10rem")], min_rem: 11.5, gap_keys: [],
        grow_max: "2rem", gap_max: "0px", narrow_rem: 3.5).table_style
      expect(style).to include("min-width: calc(11.5rem - var(--exp-nn, 0rem))")
    end
  end
end
