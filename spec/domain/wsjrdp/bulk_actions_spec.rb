# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp::BulkActions do
  let(:actions) do
    described_class.define(noun: {one: "Buchung", many: "Buchungen"}) do |a|
      a.action key: "mark", label: "Markieren", icon: :check, apply: :bulk_mark,
        hint: {one: "Markiert 1 Buchung", many: "Markiert %{count} Buchungen"},
        done: "%{count} Buchungen markiert."
      a.action key: "tag", label: "Kennzeichen setzen", icon: :tag, apply: :bulk_tag, danger: true,
        param: {name: :tag, label: "Kennzeichen", options: :tag_options, default: :default_tag},
        hint: {one: "Setzt %{target} bei 1 Buchung", many: "Setzt %{target} bei %{count} Buchungen"},
        done: "%{count} Buchungen: %{target} gesetzt.", authorize: [:update, DatevBooking]
    end
  end

  let(:host) do
    Class.new do
      def tag_options = [["Rot", "r"], ["Blau", "b"]]

      def default_tag = "b"
    end.new
  end

  it "keeps the actions in their order, found by key" do
    expect(actions.keys).to eq(%w[mark tag])
    expect(actions["tag"]).to have_attributes(label: "Kennzeichen setzen", danger: true,
      authorize: [:update, DatevBooking])
    expect(actions[:mark].param).to be_nil
    expect(actions["nope"]).to be_nil
    expect(actions.noun).to eq(one: "Buchung", many: "Buchungen")
  end

  it "names the method that partitions the selection, and builds partitions with defaults" do
    with = described_class.define do |a|
      a.action key: "p", label: "P", icon: :x, apply: :x, partition: :split, hint: {one: "a", many: "b"}, done: "d"
    end
    expect(with["p"].partition).to eq(:split)
    expect(actions["mark"].partition).to be_nil
    expect(described_class::Partition.new(affected: :rel)).to have_attributes(columns: [], groups: [])
    expect(described_class::Group.new(rows: :rel, text: "t")).to have_attributes(warning: false)
  end

  it "fills the hint and the done message" do
    expect(actions["mark"].hint_for(1)).to eq("Markiert 1 Buchung")
    expect(actions["mark"].hint_for(3)).to eq("Markiert 3 Buchungen")
    expect(actions["tag"].hint_for(2, target: "Rot")).to eq("Setzt Rot bei 2 Buchungen")
    expect(actions["tag"].done_message(2, target: "Rot")).to eq("2 Buchungen: Rot gesetzt.")
  end

  it "reads the param's options and default from the host" do
    tag = actions["tag"]

    expect(tag.options_in(host)).to eq([["Rot", "r"], ["Blau", "b"]])
    expect(tag.default_in(host)).to eq("b")
    expect(tag.target_in(host, "r")).to eq("Rot")
    expect(tag.target_in(host, "x")).to be_nil
    expect(tag.param.name).to eq("tag")
  end

  it "refuses what it cannot run" do
    base = {label: "X", icon: :x, apply: :x, hint: {one: "a", many: "b"}, done: "d"}
    define = ->(*list) { described_class.define { |a| list.each { |options| a.action(**options) } } }

    expect { define.call(base.merge(key: "Bad-Key")) }.to raise_error(ArgumentError, /must match/)
    expect { define.call(base.merge(key: "a"), base.merge(key: "a")) }.to raise_error(ArgumentError, /twice/)
    expect { define.call(base.merge(key: "a", colour: "red")) }.to raise_error(ArgumentError, /unknown options/)
    expect { define.call(base.merge(key: "a", hint: {one: "a"})) }.to raise_error(ArgumentError, /hint/)
    expect { define.call(base.merge(key: "a", apply: -> {})) }.to raise_error(ArgumentError, /apply/)
    expect { define.call(base.merge(key: "a", param: {name: :p, label: "P", options: [["a", 1]]})) }
      .to raise_error(ArgumentError, /options/)
    expect { define.call(base.merge(key: "a", partition: -> {})) }.to raise_error(ArgumentError, /partition/)
  end
end
