# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "active_support"
require "active_support/core_ext/object/blank"

# Standalone (no Rails boot, no DB): the rows object only ever calls a handful of
# relation methods, so a double that RECORDS what it was asked for is enough --
# and keeping the spec standalone means the full test boot can never be pointed
# at a shared database (see AGENTS.md, "Running tests").
module Wsjrdp; end

# The one Rails constant the file touches. Arel.sql marks a String as
# host-authored SQL; standalone it only has to hand the String back. The stub
# exists ONLY when no Rails is loaded: in a combined run (rspec spec/domain/)
# the real Arel stays untouched for every spec that follows -- a plain String
# in place of an Arel::Nodes::SqlLiteral would turn a later `select(Arel.sql(…))`
# into a quoted column name.
unless defined?(Arel)
  module Arel
    def self.sql(string) = string
  end
end

require_relative "../../../app/domain/wsjrdp/expandable_table_rows"

# Records every ORDER BY / preload / limit it is asked for and answers #page /
# #total_count the way a Kaminari-paginated relation would.
class FakeTableRelation
  attr_reader :order_by, :preloaded, :limited, :summed

  def initialize(rows = (1..3).to_a)
    @rows = rows
  end

  def reorder(sql)
    dup.tap { |rel| rel.instance_variable_set(:@order_by, sql) }
  end

  def preload(spec)
    dup.tap { |rel| rel.instance_variable_set(:@preloaded, spec) }
  end

  def limit(count)
    dup.tap { |rel| rel.instance_variable_set(:@limited, count) }
  end

  def sum(column)
    @summed = column
    42
  end

  def total_count = @rows.size
end

describe Wsjrdp::ExpandableTableRows do
  # A state that only answers what the rows object asks of it.
  def state_for(sort_list, paginated: nil)
    double("state", sort_list: sort_list, paginate: paginated || :the_page)
  end

  let(:sort) { {"date" => "bookings.booking_date", "amount" => "bookings.amount_cents"} }

  describe "a relation-backed table" do
    let(:relation) { FakeTableRelation.new }

    def rows(sort_list, **options)
      described_class.new(state_for(sort_list), relation, sort: sort, **options)
    end

    it "orders by the state's sort list, NULLS LAST, tiebreaker last" do
      table = rows([["amount", "desc"], ["date", "asc"]])
      allow(table.state).to receive(:paginate) { |rel| rel }
      expect(table.page.order_by).to eq(
        "bookings.amount_cents DESC NULLS LAST, bookings.booking_date ASC NULLS LAST, id ASC"
      )
    end

    it "drops a sort key the allow-list does not know" do
      table = rows([["secret", "desc"], ["date", "desc"]])
      allow(table.state).to receive(:paginate) { |rel| rel }
      expect(table.sort_list).to eq([["date", "desc"]])
      expect(table.page.order_by).to eq("bookings.booking_date DESC NULLS LAST, id ASC")
    end

    it "falls back to the tiebreaker alone when nothing is sorted" do
      table = rows([])
      allow(table.state).to receive(:paginate) { |rel| rel }
      expect(table.page.order_by).to eq("id ASC")
    end

    it "takes a tiebreaker that names its own direction verbatim" do
      table = rows([["date", "asc"]], tiebreaker: "accounting_entries.id DESC")
      allow(table.state).to receive(:paginate) { |rel| rel }
      expect(table.page.order_by)
        .to eq("bookings.booking_date ASC NULLS LAST, accounting_entries.id DESC")
    end

    it "appends ASC to a bare tiebreaker column" do
      table = rows([], tiebreaker: "moss_transactions.id")
      allow(table.state).to receive(:paginate) { |rel| rel }
      expect(table.page.order_by).to eq("moss_transactions.id ASC")
    end

    it "uses natural_order: instead of the tiebreaker while nothing is sorted" do
      natural = ->(rel) { rel.reorder("proposals first") }
      table = rows([], natural_order: natural)
      allow(table.state).to receive(:paginate) { |rel| rel }
      expect(table.page.order_by).to eq("proposals first")
    end

    it "lets a chosen sort take over from natural_order:" do
      natural = ->(rel) { rel.reorder("proposals first") }
      table = rows([["date", "desc"]], natural_order: natural)
      allow(table.state).to receive(:paginate) { |rel| rel }
      expect(table.page.order_by).to eq("bookings.booking_date DESC NULLS LAST, id ASC")
    end

    it "preloads the given associations on the page only" do
      table = rows([], preload: {expenses: :bookings})
      allow(table.state).to receive(:paginate) { |rel| rel }
      expect(table.page.preloaded).to eq(expenses: :bookings)
    end

    it "does not preload when nothing was given" do
      table = rows([])
      allow(table.state).to receive(:paginate) { |rel| rel }
      expect(table.page.preloaded).to be_nil
    end

    it "pages through the state" do
      table = rows([])
      expect(table.state).to receive(:paginate).once.and_return(:the_page)
      expect(table.page).to eq(:the_page)
      expect(table.page).to eq(:the_page) # memoised
    end

    it "#limit is the sorted scope without paging" do
      table = rows([["date", "desc"]], preload: :batch)
      limited = table.limit(5)
      expect(limited.limited).to eq(5)
      expect(limited.preloaded).to eq(:batch)
      expect(limited.order_by).to eq("bookings.booking_date DESC NULLS LAST, id ASC")
    end

    it "#total_count comes from the page, i.e. over the whole source" do
      table = rows([])
      allow(table.state).to receive(:paginate) { |rel| rel }
      expect(table.total_count).to eq(3)
    end

    it "#total_sum sums the declared column over the WHOLE source" do
      table = rows([["date", "desc"]], sum: :signed_base_amount)
      expect(table.total_sum).to eq(42)
      expect(relation.summed).to eq(:signed_base_amount)
    end

    it "#total_sum is nil without a sum: column" do
      expect(rows([]).total_sum).to be_nil
      expect(relation.summed).to be_nil
    end
  end

  describe "an array-backed table" do
    let(:source) do
      [{number: "1000", name: "beta", sum: 30, count: 2},
        {number: "K2", name: "alpha", sum: 10, count: 9},
        {number: "900", name: "alpha", sum: 30, count: 1}]
    end
    let(:extractors) do
      {"number" => ->(r) { r[:number].to_s },
       "name" => ->(r) { r[:name].to_s },
       "sum" => ->(r) { r[:sum] }}
    end
    let(:tiebreaker) { ->(r) { r[:number].to_s } }

    def rows(sort_list, **options)
      described_class.new(state_for(sort_list), source,
        sort: extractors, tiebreaker: tiebreaker, **options)
    end

    def paged_numbers(table)
      allow(table.state).to receive(:paginate) { |array| array }
      table.page.pluck(:number)
    end

    it "keeps the incoming order while nothing is sorted" do
      expect(paged_numbers(rows([]))).to eq(%w[1000 K2 900])
    end

    it "sorts by one extractor" do
      expect(paged_numbers(rows([["sum", "desc"]]))).to eq(%w[1000 900 K2])
    end

    it "sorts by several extractors in priority order" do
      expect(paged_numbers(rows([["name", "asc"], ["sum", "desc"]]))).to eq(%w[900 K2 1000])
    end

    it "breaks ties with the tiebreaker, so equal rows stay deterministic" do
      # name asc alone leaves the two "alpha" rows tied
      expect(paged_numbers(rows([["name", "asc"]]))).to eq(%w[900 K2 1000])
    end

    it "compares an alphanumeric number as a String, not as a number" do
      # to_i would collapse "K2" to 0 and put it first
      expect(paged_numbers(rows([["number", "asc"]]))).to eq(%w[1000 900 K2])
    end

    it "drops a sort key the extractors do not know" do
      table = rows([["secret", "asc"]])
      expect(table.sort_list).to eq([])
      expect(paged_numbers(table)).to eq(%w[1000 K2 900])
    end

    it "uses natural_order: while nothing is sorted" do
      table = rows([], natural_order: ->(array) { array.reverse })
      expect(paged_numbers(table)).to eq(%w[900 K2 1000])
    end

    it "#total_sum adds the declared key up over every row" do
      expect(rows([], sum: :count).total_sum).to eq(12)
    end

    it "insists on a Proc tiebreaker" do
      expect { described_class.new(state_for([]), source, sort: extractors) }
        .to raise_error(ArgumentError, /needs a ->\(row\)\{ comparable \} tiebreaker/)
    end
  end
end
