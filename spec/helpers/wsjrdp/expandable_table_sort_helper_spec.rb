# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The tooltips of the sort arrows: what the next click and the next
# shift-click do.
describe Wsjrdp::ExpandableTableSortHelper do
  let(:names) { {"number" => "Kostenstelle", "y26__ist" => "2026 IST", "y26__pct" => "2026 Ausschöpfung"} }

  def state(list)
    double("state", sort_list: list, sort_column_for: nil).tap do |state|
      allow(state).to receive(:sort_column_for) { |key| key.start_with?("y26") ? "y26" : key }
    end
  end

  def tip(list, key, first: "asc") = helper.et_sort_arrow_tip(state(list), key, first: first, names: names)

  it "says only what a click does while nothing else is sorted" do
    expect(tip([], "number")).to eq("Klick: aufsteigend nach „Kostenstelle“ sortieren")
    expect(tip([["number", "desc"]], "number")).to eq(
      "Klick: nicht mehr nach „Kostenstelle“ sortieren\nShift-Klick: Stufe 1 entfernen"
    )
  end

  it "offers to append a new level" do
    expect(tip([["number", "asc"]], "y26__ist", first: "desc")).to eq(
      "Klick: nur noch absteigend nach „2026 IST“ sortieren\nShift-Klick: als 2. Stufe absteigend anfügen"
    )
  end

  it "offers to step a level in place" do
    expect(tip([["number", "asc"], ["y26__ist", "desc"]], "y26__ist", first: "desc")).to eq(
      "Klick: nur noch aufsteigend nach „2026 IST“ sortieren\nShift-Klick: Stufe 2 auf aufsteigend ändern"
    )
  end

  it "offers to replace the level of another variant of the same column" do
    expect(tip([["number", "asc"], ["y26__ist", "desc"]], "y26__pct", first: "desc")).to eq(
      "Klick: nur noch absteigend nach „2026 Ausschöpfung“ sortieren\n" \
      "Shift-Klick: Stufe 2 durch „2026 Ausschöpfung“ absteigend ersetzen"
    )
  end

  it "says when a click clears everything" do
    expect(tip([["number", "asc"], ["y26__ist", "asc"]], "y26__ist", first: "desc")).to eq(
      "Klick: alle Sortierungen entfernen\nShift-Klick: Stufe 2 entfernen"
    )
  end
end
