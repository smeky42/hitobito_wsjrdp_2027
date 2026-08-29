# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The widget's "a row may bring sub-rows" half, RENDERED: one
# <tbody class="exp-group"> per row holds the row, its sub-rows and -- when the
# table is expandable -- its detail row, in that order. This is the generic kit,
# so the rows here are plain Hashes the spec builds itself; what a sub-row MEANS
# is the host's business.
describe Wsjrdp::ExpandableTableHelper do
  # A dataset of three columns, described the way any table describes its own
  # (doc/wsjrdp/expandable_table.md §1a).
  let(:column_set) do
    Wsjrdp::ExpandableTableColumns.define(css_prefix: "kitcol") do |c|
      c.column key: "name", abbr: "nm", label: "Name", default: true
      c.column key: "total", abbr: "sum", label: "Summe", numeric: true, default: true
      c.column key: "note", abbr: "nt", label: "Notiz", default: true
    end
  end

  let(:policy) do
    Wsjrdp::TableStatePolicy.new(prefix: "", columns: column_set.codec,
      cols: {default: column_set.default_keys})
  end

  # Two rows: the first brings two sub-rows, the second none.
  let(:rows) do
    [{id: 1, name: "Erste", total: "10", note: "N1",
      subs: [{label: "A", amount: "6"}, {label: "B", amount: "4"}]},
      {id: 2, name: "Zweite", total: "20", note: "N2", subs: []}]
  end

  def table_state(params = {}) = Wsjrdp::TableState.resolve(policy, params: params)

  def columns_config
    column_set.map do |col|
      col.to_table_column(cell: ->(row) { row.fetch(col.key.to_sym, "").to_s })
    end
  end

  # Renders the widget through the builder facade, with the sub-row locals under
  # test. A block gets the builder, so an example can add a selection or a class
  # lambda without a second render helper.
  def render_table(params: {}, sub_rows: ->(row) { row[:subs] }, detail: true)
    html = helper.wsjrdp_expandable_table do |t|
      t.state table_state(params), id: "kit"
      t.data rows
      t.columns columns_config
      t.row_key { |row| row[:id] }
      t.detail { |row| "Detail von #{row[:name]}" } if detail
      t.sub_rows(&sub_rows) if sub_rows
      t.sub_cell { |sub, col| (col[:key] == "name") ? sub[:label] : sub[:amount].to_s }
      yield t if block_given?
    end
    Nokogiri::HTML.fragment(html)
  end

  # The groups of the rendered table, in order.
  def groups(doc) = doc.css("table tbody.exp-group")

  describe "the row group" do
    subject(:doc) { render_table }

    it "renders one tbody.exp-group per row, whatever the row brings" do
      expect(groups(doc).size).to eq(2)
      expect(groups(doc).map { |g| g.at_css("tr.exp-row td.exp-col").text })
        .to eq(%w[Erste Zweite])
    end

    it "puts the sub-rows right after their parent, inside the same group" do
      expect(groups(doc).first.element_children.pluck("class"))
        .to eq(["exp-row", "exp-sub-row", "exp-sub-row", "exp-detail-row"])
    end

    it "ends the group with the detail row, below the sub-rows" do
      expect(groups(doc).first.element_children.last["class"]).to eq("exp-detail-row")
      expect(groups(doc).first.at_css("tr.exp-detail-row .exp-detail").text)
        .to include("Detail von Erste")
    end

    it "renders no sub-row for a row whose sub_rows are empty" do
      expect(groups(doc).last.css("tr.exp-sub-row")).to be_empty
      expect(groups(doc).last.element_children.pluck("class"))
        .to eq(["exp-row", "exp-detail-row"])
    end

    it "fills the sub-row cells from sub_cell, per column" do
      cells = groups(doc).first.css("tr.exp-sub-row").first.css("td")
      expect(cells.pluck("data-colkey")).to eq(%w[name total note])
      expect(cells.map(&:text)).to eq(%w[A 6 6])
    end

    it "marks the numeric column on a sub-row cell as it does on a head cell" do
      sub_cell = groups(doc).first.at_css("tr.exp-sub-row td[data-colkey='total']")
      expect(sub_cell["class"].split).to include("exp-col", "exp-sub-col", "kitcol-total",
        "text-end", "text-nowrap")
    end

    # A sub-row opens the group's detail like the head row above it: the same
    # disclosure attributes, pointing at the same collapse -- the group has ONE
    # detail, and no sub-row brings one of its own.
    it "gives a sub-row the head row's disclosure attributes, on the same detail" do
      head = groups(doc).first.at_css("tr.exp-row")
      target = head["data-bs-target"]
      expect(target).to eq("#kit-1")

      groups(doc).first.css("tr.exp-sub-row").each do |sub|
        expect(sub["role"]).to eq("button")
        expect(sub["tabindex"]).to eq("0")
        expect(sub["data-bs-toggle"]).to eq("collapse")
        expect(sub["data-bs-target"]).to eq(target)
        expect(sub["aria-expanded"]).to eq("false")
        expect(sub["aria-controls"]).to eq(head["aria-controls"])
        expect(sub.css(".collapse")).to be_empty
      end
    end

    it "mirrors the head row's aria-expanded on the sub-rows of an open group" do
      open_doc = render_table(params: {"o" => "1"})
      rows = groups(open_doc).first.css("tr.exp-row, tr.exp-sub-row")
      expect(rows.pluck("aria-expanded")).to eq(%w[true true true])
    end
  end

  describe "the visible columns" do
    # `?c=` hides "total" -- and a hidden column is hidden in EVERY row of the
    # group, head row and sub-rows alike.
    subject(:doc) { render_table(params: {"c" => "nm,~sum,nt"}) }

    it "leaves a hidden column out of the sub-rows as well as the head rows" do
      expect(doc.css("thead th.exp-col").pluck("data-colkey")).to eq(%w[name note])
      expect(groups(doc).first.at_css("tr.exp-sub-row").css("td").pluck("data-colkey"))
        .to eq(%w[name note])
      expect(doc.css("tr.exp-sub-row td[data-colkey='total']")).to be_empty
    end
  end

  describe "with a row selection" do
    subject(:doc) do
      render_table do |t|
        t.selection({name: "ids[]", id_field: ->(row) { row[:id] }, form: "kit-form"})
      end
    end

    it "gives a sub-row the leading selection cell, empty" do
      cells = groups(doc).first.at_css("tr.exp-sub-row").css("td")
      expect(cells.first["class"]).to eq("bk-select-cell")
      expect(cells.first.text).to eq("")
      expect(cells.first.css("input")).to be_empty
      expect(cells.pluck("data-colkey")).to eq([nil, "name", "total", "note"])
    end

    it "keeps the checkbox on the head row" do
      expect(groups(doc).first.css("tr.exp-row td.bk-select-cell input.bk-select-check").size)
        .to eq(1)
    end
  end

  describe "the class lambdas" do
    subject(:doc) do
      render_table do |t|
        t.group_class { |row| "grp-#{row[:id]}" }
        t.sub_row_class { |sub| "sub-#{sub[:label].downcase}" }
      end
    end

    it "puts group_class on the tbody and sub_row_class on the sub-row" do
      expect(groups(doc).pluck("class")).to eq(["exp-group grp-1", "exp-group grp-2"])
      expect(groups(doc).first.css("tr.exp-sub-row").pluck("class"))
        .to eq(["exp-sub-row sub-a", "exp-sub-row sub-b"])
    end
  end

  # The open detail is marked by a CLASS, not by its position: with sub-rows
  # between them the detail row is no longer the open row's next sibling, so the
  # closing border rule follows .exp-open (kept in sync by the collapse listener
  # in shared/wsjrdp/_expandable_table_js).
  describe "an open row" do
    subject(:doc) { render_table(params: {"o" => "1"}) }

    it "marks the open row's detail row, and only that one" do
      expect(groups(doc).first.at_css("tr.exp-detail-row")["class"].split)
        .to include("exp-detail-row", "exp-open")
      expect(groups(doc).last.at_css("tr.exp-detail-row")["class"]).to eq("exp-detail-row")
    end
  end

  describe "a table without sub-rows" do
    subject(:doc) { render_table(sub_rows: nil) }

    it "renders the same groups, each holding the row and its detail row" do
      expect(groups(doc).size).to eq(2)
      expect(doc.css("tr.exp-sub-row")).to be_empty
      expect(groups(doc).first.element_children.pluck("class"))
        .to eq(["exp-row", "exp-detail-row"])
    end
  end

  describe "a table without a detail" do
    subject(:doc) { render_table(detail: false) }

    it "renders the group without a detail row, the sub-rows last" do
      expect(groups(doc).first.element_children.pluck("class"))
        .to eq(["exp-row", "exp-sub-row", "exp-sub-row"])
      expect(groups(doc).first.at_css("tr.exp-row")["role"]).to be_nil
    end

    # Nothing to disclose: the sub-rows are as free of disclosure attributes as
    # the head row above them.
    it "leaves the sub-rows without disclosure attributes too" do
      sub = groups(doc).first.at_css("tr.exp-sub-row")
      expect(sub["role"]).to be_nil
      expect(sub["tabindex"]).to be_nil
      expect(sub["data-bs-toggle"]).to be_nil
      expect(sub["data-bs-target"]).to be_nil
      expect(sub["aria-expanded"]).to be_nil
    end
  end

  describe "an empty table" do
    it "keeps its single 'nothing found' row, in a plain tbody" do
      html = helper.wsjrdp_expandable_table do |t|
        t.state table_state, id: "kit"
        t.data []
        t.columns columns_config
        t.row_key { |row| row[:id] }
      end
      doc = Nokogiri::HTML.fragment(html)
      expect(doc.css("table tbody.exp-group")).to be_empty
      expect(doc.at_css("table tbody tr td").text).to include("Keine Einträge gefunden.")
    end
  end
end
