# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The bulk-action bar of the widget, RENDERED (t.bulk_actions): the form the
# selection's checkboxes name, a button per inline action that opens its panel
# (the param's select, the hint, the preview box, the button that runs it),
# "Weitere" for the rest, and nothing the user may not run.
describe Wsjrdp::ExpandableTableHelper do
  let(:column_set) do
    Wsjrdp::ExpandableTableColumns.define(css_prefix: "kitcol") do |c|
      c.column key: "name", abbr: "nm", label: "Name", default: true
    end
  end

  let(:policy) do
    Wsjrdp::TableStatePolicy.new(prefix: "", columns: column_set.codec, cols: {default: column_set.default_keys})
  end

  let(:rows) { [{id: 1, name: "Erste", atom: "a"}, {id: 2, name: "Zweite", atom: "b"}] }

  let(:actions) do
    Wsjrdp::BulkActions.define(noun: {one: "Zeile", many: "Zeilen"}) do |a|
      a.action key: "first", label: "Erste Aktion", icon: :check, apply: :x,
        hint: {one: "Eins", many: "%{count} Stück"}, done: "d"
      a.action key: "pick", label: "Wert setzen", icon: :tag, apply: :x,
        param: {name: :value, label: "Wert", options: :value_options, default: "b"},
        hint: {one: "Setzt %{target}", many: "Setzt %{target} bei %{count}"}, done: "d"
      a.action key: "third", label: "Dritte Aktion", icon: :times, apply: :x, danger: true,
        hint: {one: "Drei", many: "Drei"}, done: "d"
      a.action key: "secret", label: "Geheim", icon: :lock, apply: :x, authorize: [:bulk_spec, :nobody],
        hint: {one: "G", many: "G"}, done: "d"
    end
  end

  before do
    controller.define_singleton_method(:value_options) { [["Alpha", "a"], ["Beta", "b"]] }
    allow(helper).to receive(:can?) { |action, subject| !(action == :bulk_spec && subject == :nobody) }
  end

  def render_table(inline: 2, with_selection: true, preview_url: "/bulk/preview")
    html = helper.wsjrdp_expandable_table do |t|
      t.state Wsjrdp::TableState.resolve(policy, params: {}), id: "kit"
      t.data rows
      t.columns(column_set.map { |col| col.to_table_column(cell: ->(row) { row[:name] }) })
      t.row_key { |row| row[:id] }
      if with_selection
        t.selection({name: "ids[]", id_field: ->(row) { row[:id] }, form: "kit-bulk", all_param: "select_all",
                     only_selected: true, total_count: 2, row_data: ->(row) { {atom: row[:atom], amount: 100} }})
      end
      t.bulk_actions actions, url: "/bulk", preview_url: preview_url, inline: inline,
        totals: {"all" => [2, 200], "a" => [1, 100]}, sum: true, quickselect: {"a" => "Gruppe A"}
    end
    Nokogiri::HTML.fragment(html)
  end

  subject(:doc) { render_table }

  it "is the form the selection posts to, the box of the actions, right above the table" do
    form = doc.at_css(".bk-select-scope > form#kit-bulk.bk-bulk-form.bk-bulk-box")
    expect(form["action"]).to eq("/bulk")
    expect(form.to_h).to include("data-all-count" => "2", "data-all-sum" => "200", "data-a-count" => "1",
      "data-sum" => "true", "data-turbo-frame" => "_top", "data-noun-many" => "Zeilen",
      "data-preview-url" => "/bulk/preview")
    expect(form.at_css("input.bk-bulk-action[name=bulk_action]")).to be_present
    expect(doc.at_css(".bk-bulk-status input.bk-select-all-field[name=select_all]")["form"]).to eq("kit-bulk")
    expect(doc.css("input.bk-select-check").pluck("form")).to all(eq("kit-bulk"))
    # The toolbar no longer carries the plain selection bar.
    expect(doc.css(".bk-select-bar").size).to eq(1)
    children = doc.at_css(".bk-select-scope").element_children
    status = children.index { |el| el["class"].to_s.include?("bk-bulk-foot") }
    expect(status).to be < children.index { |el| el["class"].to_s.include?("exp-table-wrap") }
  end

  it "is always there, with 0 selected, without the clear link and with the actions disabled" do
    status = doc.at_css(".bk-bulk-status.bk-select-bar")
    expect(status["style"].to_s).not_to include("display: none")
    expect(status.at_css(".bk-select-info").text).to eq("0 ausgewählt.")
    expect(status.at_css("a.bk-select-clear")["style"]).to include("display: none")
    expect(doc.at_css(".bk-bulk-box .bk-select-info")).to be_nil
    expect(doc.css(".bk-bulk-box .dropdown-toggle").pluck("disabled")).to all(be_present)
  end

  it "puts the quick-select between the actions and the line of how many are selected, the switch in that line" do
    scope = doc.at_css(".bk-select-scope")
    expect(scope.element_children.map { |el| el["class"].to_s[/bk-bulk-(box|quick|foot)/] }.compact)
      .to eq(%w[bk-bulk-box bk-bulk-quick bk-bulk-foot])
    expect(scope.css(".bk-bulk-quick button").map { |button| button.text.squish })
      .to eq(["Keine", "Alle (2)", "Gruppe A", "nur (1)"])
    expect(scope.css(".bk-bulk-quick button[data-quick-atom=a]").pluck("data-quick-mode")).to eq(%w[add only])
    expect(scope.at_css(".bk-bulk-quick .bk-only-selected-toggle")).to be_nil
    expect(scope.at_css(".bk-bulk-status .bk-only-selected-toggle")["data-form"]).to eq("kit-bulk")
    expect(scope.at_css(".bk-bulk-status a.bk-select-all-pages")).to be_present
  end

  it "shows each inline action as a button that opens its panel, which runs it" do
    bar = doc.at_css(".bk-bulk-box")
    toggles = bar.css(".dropdown > button.btn-outline-primary.dropdown-toggle[data-bs-toggle=dropdown]")
    expect(toggles.map { |toggle| toggle.text.squish }).to eq(["Erste Aktion", "Wert setzen"])

    first = bar.at_css(".bk-bulk-popover [data-bulk-panel=first]")
    run = first.at_css("button.btn-primary[data-bulk-action=first]")
    expect(run.text.squish).to eq("Erste Aktion")
    expect(run.to_h).to include("data-hint-one" => "Eins", "data-hint-many" => "%{count} Stück")
    expect(first.at_css(".bk-bulk-hint[data-bulk-hint-for=first]")).to be_present
    expect(first.at_css(".bk-bulk-preview")).to be_present
    expect(first.at_css("select")).to be_nil

    select = bar.at_css(".bk-bulk-popover select[name=value][data-bulk-param-for=pick]")
    expect(select.css("option").map { |o| [o.text, o["value"]] }).to eq([%w[Alpha a], %w[Beta b]])
    expect(select.at_css("option[selected]")["value"]).to eq("b")
    expect(bar.at_css(".bk-bulk-popover button[data-bulk-action=pick]")).to be_present
    expect(bar.at_css(".bk-bulk-hint[data-bulk-hint-for=pick]")).to be_present
  end

  it "has no preview box without a preview endpoint" do
    expect(render_table(preview_url: nil).at_css(".bk-bulk-preview")).to be_nil
  end

  it "puts the actions beyond `inline` under Weitere and leaves out what the user may not run" do
    more = doc.css(".bk-bulk-box > .dropdown").last
    expect(more.at_css("button.dropdown-toggle").text.squish).to eq("Weitere")
    expect(more.css("button.dropdown-item[data-bulk-show]").pluck("data-bulk-show")).to eq(["third"])
    panel = more.at_css("[data-bulk-panel=third][hidden]")
    expect(panel.at_css("button.btn-danger[data-bulk-action=third]")).to be_present
    expect(panel.at_css(".bk-bulk-preview")).to be_present
    expect(doc.at_css("[data-bulk-action=secret]")).to be_nil

    all_inline = render_table(inline: 5)
    expect(all_inline.css(".bk-bulk-box [data-bulk-action]").pluck("data-bulk-action").uniq)
      .to eq(%w[first pick third])
    expect(all_inline.at_css(".bk-bulk-box button.btn-outline-danger.dropdown-toggle")).to be_present
  end

  it "needs a selection with a form" do
    expect { render_table(with_selection: false) }.to raise_error(ArgumentError, /no selection/)
  end

  it "puts the switch into the plain selection bar of a table without bulk actions" do
    html = helper.wsjrdp_expandable_table do |t|
      t.state Wsjrdp::TableState.resolve(policy, params: {}), id: "kit"
      t.data rows
      t.columns(column_set.map { |col| col.to_table_column(cell: ->(row) { row[:name] }) })
      t.row_key { |row| row[:id] }
      t.selection({name: "ids[]", id_field: ->(row) { row[:id] }, form: "kit-plain", all_param: "select_all",
                   only_selected: true, total_count: 2})
    end
    plain = Nokogiri::HTML.fragment(html)

    expect(plain.at_css(".bk-select-bar:not(.bk-bulk-bar) .bk-only-selected-toggle")["data-form"]).to eq("kit-plain")
  end
end
