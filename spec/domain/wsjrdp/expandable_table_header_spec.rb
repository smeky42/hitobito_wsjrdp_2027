# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp::ExpandableTableHeader do
  def columns(&block)
    Wsjrdp::ExpandableTableColumns.define(&block).map { |col| col.to_table_column(cell: ->(_row) {}) }
  end

  def header(cols, shown: nil)
    cols = cols.select { |col| shown.include?(col[:key]) } if shown
    described_class.new(columns: cols, header_align: ->(_col) {})
  end

  # Per row: [kind, header key or label, covered keys, rowspan, align, wrap].
  def layout(rows)
    rows.map do |cells|
      cells.map do |cell|
        [cell.kind, (cell.kind == :group) ? cell.label : cell.headers.pluck(:key).join("+"),
          cell.columns.pluck(:key), cell.rowspan, cell.align, cell.wrap]
      end
    end
  end

  let(:name_columns) do
    columns do |c|
      c.column key: "id", width: "4rem"
      c.column key: "label", merge: "NAME", width: "6rem"
      c.column key: "key", merge: "NAME", width: "2rem"
      c.column key: "sub", merge: "NAME", width: "5rem"
      c.column key: "note", width: "6rem"
      c.merge_header "NAME", layouts: [[%w[label key sub]], [%w[label], %w[key sub]],
        {rows: [%w[label], %w[key sub]], wrap: true}]
    end
  end

  it "has one row of headers without layouts or groups" do
    cols = columns do |c|
      c.column key: "a"
      c.column key: "b"
    end
    expect(header(cols).variants.size).to eq(1)
    expect(layout(header(cols).variants.first)).to eq([[[:column, "a", %w[a], 1, nil, false],
      [:column, "b", %w[b], 1, nil, false]]])
  end

  it "makes a variant per layout, compact first, the others reaching down" do
    variants = header(name_columns).variants

    expect(variants.size).to eq(3)
    expect(layout(variants[0])).to eq([[[:column, "id", %w[id], 1, nil, false],
      [:column, "label", %w[label], 1, "start", false], [:column, "key", %w[key], 1, "center", false],
      [:column, "sub", %w[sub], 1, "end", false], [:column, "note", %w[note], 1, nil, false]]])
    expect(layout(variants[1])).to eq([
      [[:column, "id", %w[id], 2, nil, false], [:column, "label", %w[label key sub], 1, "start", false],
        [:column, "note", %w[note], 2, nil, false]],
      # The first entry of a row reaches back to the run's start.
      [[:column, "key", %w[label key], 1, "start", false], [:column, "sub", %w[sub], 1, "end", false]]
    ])
    expect(layout(variants[2]).last.map(&:last)).to eq([true, true])
  end

  it "drops a hidden column's header and a row left empty" do
    variants = header(name_columns, shown: %w[label sub note]).variants

    expect(layout(variants[1])).to eq([
      [[:column, "label", %w[label sub], 1, "start", false], [:column, "note", %w[note], 2, nil, false]],
      [[:column, "sub", %w[label sub], 1, "start", false]]
    ])
    expect(layout(header(name_columns, shown: %w[label note]).variants.last))
      .to eq([[[:column, "label", %w[label], 1, nil, false], [:column, "note", %w[note], 1, nil, false]]])
  end

  it "keeps a column group on two rows next to a deeper layout" do
    cols = columns do |c|
      c.column key: "wsj", group: "Rolle"
      c.column key: "cont", group: "Rolle"
      c.column key: "a", merge: "M"
      c.column key: "b", merge: "M"
      c.column key: "c", merge: "M"
      c.merge_header "M", [%w[a], %w[b], %w[c]]
    end
    rows = layout(header(cols).variants.first)

    expect(rows.size).to eq(3)
    expect(rows[0].first).to eq([:group, "Rolle", %w[wsj cont], 2, nil, false])
    expect(rows[2].pluck(1)).to eq(%w[wsj cont c])
  end

  it "sets the headers of a flow row one after the other in one cell" do
    cols = columns do |c|
      c.column key: "label", merge: "NAME"
      c.column key: "key", merge: "NAME"
      c.column key: "sub", merge: "NAME"
      c.merge_header "NAME", [%w[label], {cells: %w[key sub], flow: true, justify: "between", separator: "·"}]
    end
    flow = header(cols).variants.first.last.first

    expect([flow.kind, flow.headers.pluck(:key), flow.colspan, flow.justify, flow.separator])
      .to eq([:flow, %w[key sub], 3, "between", "·"])
  end

  it "takes an entry's own alignment and span" do
    cols = columns do |c|
      c.column key: "a", merge: "M"
      c.column key: "b", merge: "M"
      c.column key: "c", merge: "M"
      c.merge_header "M", [[{key: "a", span: 2, align: "center"}, "c"]]
    end
    expect(layout(header(cols).variants.first)).to eq([[[:column, "a", %w[a b], 1, "center", false],
      [:column, "c", %w[c], 1, "end", false]]])
  end
end

describe Wsjrdp::ExpandableTableHeaderLayout do
  def build(layouts) = described_class.new("NAME", layouts, members: %w[label key])

  it "refuses what it cannot lay out" do
    expect { build([]) }.to raise_error(ArgumentError, /no layout/)
    expect { build([[%w[label nope]]]) }.to raise_error(ArgumentError, /nope is no column/)
    expect { build([[[{key: "label", align: "left"}]]]) }.to raise_error(ArgumentError, /align/)
    expect { build([[[{key: "label", span: 0}]]]) }.to raise_error(ArgumentError, /span/)
    expect { build([[[]]]) }.to raise_error(ArgumentError, /empty row/)
    expect { build([[{cells: %w[label], flow: true, justify: "around"}]]) }.to raise_error(ArgumentError, /justify/)
  end

  it "refuses a merge_header of a merge no column has" do
    expect do
      Wsjrdp::ExpandableTableColumns.define do |c|
        c.column key: "a"
        c.merge_header "X", [%w[a]]
      end
    end.to raise_error(ArgumentError, /no column has this merge/)
  end
end
