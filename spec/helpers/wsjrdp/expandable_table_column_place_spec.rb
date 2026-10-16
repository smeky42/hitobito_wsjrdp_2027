# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Pinned columns (pinned:) and tristate ones (visibility: :tristate),
# RENDERED: their place in the table and in the columns menu, and how a
# tristate column shows.
describe Wsjrdp::ExpandableTableHelper do
  let(:column_set) do
    Wsjrdp::ExpandableTableColumns.define(css_prefix: "pc") do |c|
      c.column key: "tail", abbr: "tl", label: "Ende", width: "4rem", pinned: :end, default: true
      c.column key: "id", abbr: "id", label: "ID", width: "4rem", default: true
      c.column key: "name", abbr: "nm", label: "Name", width: "8rem", default: true
      c.column key: "who", abbr: "wh", label: "Von", width: "6rem", visibility: :tristate, default: :auto,
        fallback: :cell
      c.column key: "head", abbr: "hd", label: "Anfang", width: "4rem", pinned: :start, default: true
    end
  end

  let(:rows) { [{id: 1, name: "A", who: "W", head: "H", tail: "T"}] }

  def policy = Wsjrdp::TableStatePolicy.new(prefix: "", columns: column_set.codec,
    cols: {default: column_set.default_keys})

  def render_table(params = {})
    state = Wsjrdp::TableState.resolve(policy, params: params)
    html = helper.wsjrdp_expandable_table do |t|
      t.state state, id: "pc"
      t.data rows
      t.columns(column_set.map { |col| col.to_table_column(cell: ->(row) { row.fetch(col.key.to_sym).to_s }) },
        menu: true)
      t.row_key { |row| row[:id] }
      t.detail { |row| content_tag(:span, "nur ohne Von", data: {exp_if_hidden: "who"}) }
    end
    Nokogiri::HTML.fragment(html)
  end

  def shown_keys(doc) = doc.css("tbody tr td[data-colkey]").pluck("data-colkey")

  it "keeps pinned columns at the start and the end, whatever the param's order" do
    expect(shown_keys(render_table)).to eq(%w[head id name who tail])
    expect(shown_keys(render_table("c" => "tl,nm,hd,id"))).to eq(%w[head name id tail])
  end

  it "lists pinned columns in the menu without a drag handle" do
    items = render_table.css(".exp-cols-item.exp-cols-col")
    expect(items.pluck("data-key")).to eq(%w[head id name who tail])
    expect(items.first["draggable"]).to be_nil
    expect(items.first["data-pinned"]).to eq("start")
    expect(items[1]["draggable"]).to eq("true")
  end

  it "shows a tristate column in auto by default, giving way where the table would scroll" do
    doc = render_table
    who = doc.at_css(".exp-cols-col[data-key=who]")
    expect(who["data-mode"]).to eq("auto")
    expect(who["data-next-mode"]).to eq("always")
    expect(who.at_css("button.exp-cols-tristate[aria-checked=mixed]")).to be_present
    expect(doc.at_css("td[data-colkey=who].exp-no-narrow")).to be_present
    expect(doc.at_css("input.exp-cols-input")["value"]).to include("wh.a")
    # "Standard-Spalten" (an empty param) brings the default back too.
    expect(render_table("c" => "").at_css(".exp-cols-col[data-key=who]")["data-mode"]).to eq("auto")
  end

  it "shows a tristate column always, or never, as the param says" do
    expect(render_table("c" => "hd,id,nm,wh,tl").at_css("td[data-colkey=who].exp-no-narrow")).to be_nil
    expect(shown_keys(render_table("c" => "hd,id,nm,~wh,tl"))).not_to include("who")
    expect(render_table("c" => "hd,id,nm,~wh,tl").at_css(".exp-cols-col[data-key=who]")["data-mode"]).to eq("never")
  end

  it "puts a column's fallback into the detail, marked to show while the column does not" do
    doc = render_table
    expect(doc.at_css(".exp-detail .exp-fallback[data-exp-if-hidden=who]").text.squish).to eq("Von W")
    expect(doc.at_css(".exp-detail [data-exp-if-any-hidden]")).to be_present
    css = doc.css("style").map(&:text).join
    expect(css).to include("@container exp-pc (width >= ").and include('[data-exp-if-hidden~="who"]')
    expect(css).to include('.exp-detail [data-exp-if-hidden~="head"]')
  end
end
