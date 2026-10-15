# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The widget's widths, RENDERED: target widths (Wsjrdp::ExpandableTableLayout),
# truncating and sticky columns -- and a table without them, which renders as
# it always did.
describe Wsjrdp::ExpandableTableHelper do
  let(:wide_columns) do
    Wsjrdp::ExpandableTableColumns.define(css_prefix: "wcol") do |c|
      c.column key: "id", abbr: "id", label: "ID", width: "4rem", sticky: true, default: true
      c.column key: "name", abbr: "nm", label: "Name", width: "8rem", target_width: "13rem", truncate: true,
        sticky: true, default: true
      c.column key: "kind", abbr: "kd", label: "Art", width: "7rem", target_width: "9rem", grow: 1, default: true
      c.column key: "note", abbr: "nt", label: "Notiz", width: "6rem", default: true
    end
  end

  let(:plain_columns) do
    Wsjrdp::ExpandableTableColumns.define(css_prefix: "pcol") do |c|
      c.column key: "id", abbr: "id", label: "ID", width: "4rem", default: true
      c.column key: "name", abbr: "nm", label: "Name", width: "8rem", grow: 1, default: true
      c.column key: "note", abbr: "nt", label: "Notiz", width: "6rem", default: true
    end
  end

  let(:rows) do
    [{id: 1, name: "Eine sehr lange Bezeichnung", kind: "A", note: "N1", subs: [{label: "Teil"}]},
      {id: 2, name: "Kurz", kind: "B", note: "N2", subs: []}]
  end

  def policy(column_set) = Wsjrdp::TableStatePolicy.new(prefix: "", columns: column_set.codec,
    cols: {default: column_set.default_keys})

  def render_table(column_set, params: {}, condensed: false, selection: true, gaps: true)
    state = Wsjrdp::TableState.resolve(policy(column_set), params: params)
    html = helper.wsjrdp_expandable_table do |t|
      t.state state, id: "wt"
      t.data rows
      t.columns(column_set.map { |col| col.to_table_column(cell: ->(row) { row.fetch(col.key.to_sym).to_s }) })
      t.row_key { |row| row[:id] }
      t.detail { |row| "Detail #{row[:id]}" }
      t.sub_rows { |row| row[:subs] }
      t.sub_cell { |sub, col| (col[:key] == "name") ? sub[:label] : "" }
      t.footer { |col| (col[:key] == "id") ? "Σ" : "" }
      t.gaps max: "1.5rem", grow_max: "1rem" if gaps
      t.condensed if condensed
      if selection
        t.selection({name: "ids[]", id_field: ->(row) { row[:id] }, form: "f"})
      end
    end
    [html, Nokogiri::HTML.fragment(html)]
  end

  describe "a table with target widths, truncation and sticky columns" do
    let(:rendered) { render_table(wide_columns) }
    let(:html) { rendered.first }
    let(:doc) { rendered.last }

    it "reckons its widths with the layout" do
      table = doc.at_css("table.bookings-table")
      expect(table[:class]).to include("exp-has-sticky")
      expect(table[:style]).to include("--exp-c1: clamp(", "--exp-c2: clamp(", "--exp-t: calc(", "--exp-g: clamp(")
      expect(doc.css("colgroup col").pluck(:style)).to eq([
        "width: 2rem",
        "width: calc(4rem + var(--exp-g))",
        "width: calc(8rem + min(1 * var(--exp-c1), 5rem) + var(--exp-g))",
        "width: calc(7rem + min(1 * var(--exp-c1), 2rem) + 1 * var(--exp-c2) + var(--exp-g))",
        "width: 6rem"
      ])
      expect(doc.at_css(".exp-filter-limit, .bk-select-scope")[:style])
        .to eq("max-width: calc(27rem + 7rem + 1 * 1rem + 3 * 1.5rem)")
    end

    it "keeps the leading sticky columns and the selection in view, in every row" do
      left = ->(cells) { cells.pluck(:style) }
      expect(left.call(doc.css("thead th.exp-sticky")))
        .to eq(["width: 2rem; left: 0px", "width: calc(4rem + var(--exp-g)); left: calc(2rem)",
          "width: calc(8rem + min(1 * var(--exp-c1), 5rem) + var(--exp-g)); left: calc(2rem + calc(4rem + var(--exp-g)))"])
      first_row = doc.at_css("tr.exp-row")
      expect(left.call(first_row.css("td.exp-sticky")))
        .to eq(["left: 0px", "left: calc(2rem)", "left: calc(2rem + calc(4rem + var(--exp-g)))"])
      expect(doc.css("tr.exp-sub-row td.exp-sticky").size).to eq(3)
      expect(doc.css("tr.exp-footer-row td.exp-sticky").size).to eq(3)
      expect(doc.css(".exp-sticky-last").pluck("data-colkey").uniq).to eq(["name"])
      expect(doc.css("td.exp-sticky[data-colkey='kind']")).to be_empty
    end

    it "truncates the body cells of a truncating column, not its header" do
      expect(doc.css("tr.exp-row td.exp-truncate").pluck("data-colkey")).to eq(%w[name name])
      expect(doc.css("tr.exp-sub-row td.exp-truncate, tr.exp-footer-row td.exp-truncate").size).to eq(2)
      expect(doc.css("th.exp-truncate")).to be_empty
    end

    it "brings its styles and its script along" do
      expect(html).to include(".bookings-table.exp-has-sticky", "window.__expTableLayout", "wsjrdp-tip-box")
    end

    it "lets a sticky column moved behind another one scroll" do
      _html, doc = render_table(wide_columns, params: {"c" => "nt,nm,id,kd"})
      expect(doc.css(".exp-sticky")).to be_empty
      expect(doc.at_css("table")[:class]).not_to include("exp-has-sticky")
    end

    it "takes none of it in a condensed table" do
      html, doc = render_table(wide_columns, condensed: true)
      expect(doc.css(".exp-sticky, .exp-truncate, colgroup")).to be_empty
      expect(doc.at_css("table")[:style]).not_to include("--exp-c1")
      expect(html).not_to include("window.__expTableLayout")
    end
  end

  describe "a table without them" do
    it "renders as it always did: no layout styles, no script, no style on a cell" do
      html, doc = render_table(plain_columns)
      expect(doc.at_css("table")[:style]).to include("--exp-c: clamp(")
      expect(doc.at_css("table")[:style]).not_to include("--exp-c1")
      expect(doc.css("td[style], .exp-sticky, .exp-truncate")).to be_empty
      expect(doc.at_css("table")[:class]).not_to include("exp-has-sticky")
      expect(html).not_to include("window.__expTableLayout", ".bookings-table.exp-has-sticky")
    end
  end
end
