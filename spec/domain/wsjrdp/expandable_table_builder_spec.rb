# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "active_support"
require "active_support/core_ext/enumerable"
require "active_support/core_ext/object/blank"

module Wsjrdp; end
require_relative "../../../app/domain/wsjrdp/expandable_table_builder"

describe Wsjrdp::ExpandableTableBuilder do
  subject(:builder) { described_class.new }

  describe "#to_locals" do
    it "returns an empty hash for a fresh builder" do
      expect(builder.to_locals).to eq({})
    end
  end

  describe "#state" do
    let(:state) { double("state", prefix: "people") }

    it "sets :state and derives :id_prefix from the state's prefix" do
      builder.state(state)
      expect(builder.to_locals[:state]).to equal(state)
      expect(builder.to_locals[:id_prefix]).to eq("people")
    end

    it "uses the id: override for :id_prefix when given" do
      builder.state(state, id: "ppl")
      expect(builder.to_locals).to include(state: state, id_prefix: "ppl")
    end

    it "sets :id_prefix to nil for the empty prefix and no id: given" do
      builder.state(double("state", prefix: ""))
      expect(builder.to_locals[:id_prefix]).to be_nil
    end
  end

  describe "#rows" do
    let(:page) { [{id: 1}, {id: 2}] }
    let(:state) { double("state", prefix: "bk") }
    let(:table_rows) { double("rows", state: state, page: page) }

    it "sets state, id_prefix, rows and pagination from the one object" do
      builder.rows(table_rows)
      locals = builder.to_locals
      expect(locals[:state]).to equal(state)
      expect(locals[:id_prefix]).to eq("bk")
      expect(locals[:rows]).to equal(page)
      expect(locals[:pagination]).to equal(page)
    end

    it "takes the id: override for the DOM id prefix" do
      builder.rows(table_rows, id: "cost_center")
      expect(builder.to_locals[:id_prefix]).to eq("cost_center")
    end

    it "falls back to nil for an unprefixed table with no id:" do
      builder.rows(double("rows", state: double("state", prefix: ""), page: page))
      expect(builder.to_locals[:id_prefix]).to be_nil
    end
  end

  describe "#data" do
    it "sets :rows and :pagination to the same object by default" do
      rows = [{id: 1}, {id: 2}]
      builder.data(rows)
      locals = builder.to_locals
      expect(locals[:rows]).to equal(rows)
      expect(locals[:pagination]).to equal(rows)
    end

    it "accepts a separate pagination: override" do
      rows = [{id: 1}]
      pag = double("pagination")
      builder.data(rows, pagination: pag)
      locals = builder.to_locals
      expect(locals[:rows]).to equal(rows)
      expect(locals[:pagination]).to equal(pag)
    end
  end

  describe "#columns" do
    it "sets :columns and :columns_menu" do
      cols = [[:name, "Name"], [:age, "Age"]]
      builder.columns(cols, menu: true)
      locals = builder.to_locals
      expect(locals[:columns]).to equal(cols)
      expect(locals[:columns_menu]).to be true
    end

    it "defaults :columns_menu to false" do
      builder.columns([])
      expect(builder.to_locals[:columns_menu]).to be false
    end

    it "does not carry default column keys any more (they live in the policy)" do
      builder.columns([])
      expect(builder.to_locals).not_to have_key(:default_column_keys)
    end

    it "does not set :extra_columns when extra: is not given" do
      builder.columns([])
      expect(builder.to_locals).not_to have_key(:extra_columns)
    end

    it "sets :extra_columns when extra: is given" do
      extra = [[:score, "Score"]]
      builder.columns([], extra: extra)
      expect(builder.to_locals[:extra_columns]).to equal(extra)
    end
  end

  describe "block methods" do
    %i[row_key detail_page detail detail_src detail_top detail_extra row_class
      sub_cell sub_row_class group_class].each do |method|
      it "##{method} stores the block as a Proc" do
        blk = proc { |row| row }
        builder.send(method, &blk)
        expect(builder.to_locals[method]).to equal(blk)
      end
    end

    # The trailing action cell is gone: a row's own page is reached through the
    # detail's header line (#detail_page), never through an icon in the row.
    it "has no #action any more" do
      expect(builder).not_to respond_to(:action)
    end
  end

  describe "#detail_link" do
    def link(label, &block)
      builder.detail_link(label: label, icon: :wallet, title: "#{label} öffnen",
        title_new_tab: "#{label} in neuem Tab öffnen", &block)
    end

    it "collects the declaration and its URL block" do
      blk = proc { |row| row[:url] }
      link("In Moss", &blk)
      expect(builder.to_locals[:detail_links])
        .to eq([{label: "In Moss", icon: :wallet, title: "In Moss öffnen",
                 title_new_tab: "In Moss in neuem Tab öffnen", url: blk}])
    end

    it "keeps several links in declaration order" do
      link("Erster") { "/a" }
      link("Zweiter") { "/b" }
      expect(builder.to_locals[:detail_links].pluck(:label)).to eq(%w[Erster Zweiter])
    end

    it "sets no :detail_links key when none is declared" do
      expect(builder.to_locals).not_to have_key(:detail_links)
    end
  end

  # A row may bring rows of its own. The two halves belong together: #sub_rows
  # says WHICH rows, #sub_cell how one of their cells is rendered -- so the
  # builder refuses the half declaration instead of failing at the first row
  # that brings a sub-row.
  describe "sub-rows" do
    it "#sub_rows stores the block, alongside #sub_cell" do
      subs = proc { |row| row[:children] }
      cell = proc { |sub, col| sub[col[:key]] }
      builder.sub_rows(&subs)
      builder.sub_cell(&cell)
      locals = builder.to_locals
      expect(locals[:sub_rows]).to equal(subs)
      expect(locals[:sub_cell]).to equal(cell)
    end

    it "sets none of the four keys when nothing is declared" do
      expect(builder.to_locals.keys)
        .not_to include(:sub_rows, :sub_cell, :sub_row_class, :group_class)
    end

    it "#to_locals refuses sub_rows without a sub_cell, naming the missing local" do
      builder.sub_rows { |row| row[:children] }
      expect { builder.to_locals }
        .to raise_error(ArgumentError, /sub_rows but no sub_cell.*sub_cell\(sub, col\)/m)
    end

    it "accepts a sub_cell on its own (a table that declares no sub_rows yet)" do
      builder.sub_cell { |sub, col| sub[col[:key]] }
      expect(builder.to_locals).to have_key(:sub_cell)
    end
  end

  describe "#sort" do
    it "defaults to multi: true" do
      builder.sort
      expect(builder.to_locals).to include(multi_sort: true)
    end

    it "sets the single-sort display mode" do
      builder.sort(multi: false)
      expect(builder.to_locals[:multi_sort]).to be false
    end

    it "does not carry a default sort any more (it lives in the policy)" do
      builder.sort
      expect(builder.to_locals).not_to have_key(:default_sort)
    end
  end

  describe "#paging" do
    it "sets :per_options" do
      builder.paging(per_options: [25, 50, 100])
      expect(builder.to_locals[:per_options]).to eq([25, 50, 100])
    end

    it "falls back to the widget's own page-size steps, so a bare t.paging suffices" do
      builder.paging
      expect(builder.to_locals[:per_options]).to eq(described_class::DEFAULT_PER_OPTIONS)
      expect(described_class::DEFAULT_PER_OPTIONS).to include(:all)
    end

    it "does not carry a default page size any more (it lives in the policy)" do
      builder.paging(per_options: [10, 20])
      expect(builder.to_locals).not_to have_key(:default_per)
    end
  end

  describe "scalar setters" do
    it "#filter stores the config" do
      cfg = {field: "status", options: %w[active inactive]}
      builder.filter(cfg)
      expect(builder.to_locals[:filter]).to equal(cfg)
    end

    it "#filter takes keywords too, and stays nil without either" do
      builder.filter(apply_url: "/apply", presets: [])
      expect(builder.to_locals[:filter]).to eq({apply_url: "/apply", presets: []})
      described_class.new.tap do |empty|
        empty.filter(nil)
        expect(empty.to_locals[:filter]).to be_nil
      end
    end

    # Presets are declared in ONE place per table -- the controller's policy or
    # the view -- so the builder refuses the ambiguous case, naming the table.
    it "#to_locals refuses filter presets declared in the policy AND in the view" do
      filter = double("filter", presets: [double("preset")])
      builder.state(double("state", prefix: "bk", store_key: "fin/x#index|bk", filter: filter))
      builder.filter(apply_url: "/apply", presets: [{key: "a", label: "A", slots: []}])
      expect { builder.to_locals }
        .to raise_error(ArgumentError, /fin\/x#index\|bk.*prefix "bk".*declare them once/m)
    end

    it "#to_locals accepts view presets when the policy declares none" do
      filter = double("filter", presets: [])
      builder.state(double("state", prefix: "bk", store_key: "fin/x#index|bk", filter: filter))
      builder.filter(apply_url: "/apply", presets: [{key: "a", label: "A", slots: []}])
      expect(builder.to_locals[:filter][:presets].size).to eq(1)
    end

    it "#summary stores the text" do
      builder.summary("42 entries")
      expect(builder.to_locals[:summary]).to eq("42 entries")
    end

    it "#selection stores the config" do
      cfg = {mode: :multi}
      builder.selection(cfg)
      expect(builder.to_locals[:selection]).to equal(cfg)
    end

    it "#condensed defaults to true" do
      builder.condensed
      expect(builder.to_locals[:condensed]).to be true
    end

    it "#condensed accepts an explicit value" do
      builder.condensed(false)
      expect(builder.to_locals[:condensed]).to be false
    end
  end

  describe "builder pattern accumulation" do
    it "accumulates all calls into one hash" do
      rows = [{id: 1}]
      cols = [[:name, "Name"]]
      state = double("state", prefix: "tbl")
      detail_block = proc { |r| r[:name] }

      builder.state(state, id: "t")
      builder.data(rows)
      builder.columns(cols, menu: true)
      builder.sort(multi: false)
      builder.paging(per_options: [25, 50])
      builder.detail(&detail_block)
      builder.condensed
      builder.summary("1 row")

      locals = builder.to_locals

      expect(locals[:state]).to equal(state)
      expect(locals[:id_prefix]).to eq("t")
      expect(locals[:rows]).to equal(rows)
      expect(locals[:columns]).to equal(cols)
      expect(locals[:columns_menu]).to be true
      expect(locals[:multi_sort]).to be false
      expect(locals[:per_options]).to eq([25, 50])
      expect(locals[:detail]).to equal(detail_block)
      expect(locals[:condensed]).to be true
      expect(locals[:summary]).to eq("1 row")
    end
  end
end
