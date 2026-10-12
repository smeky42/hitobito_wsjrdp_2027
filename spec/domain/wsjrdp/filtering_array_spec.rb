# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Filtering arrays with the CNF filter: both strategies give the same rows for
# every operator, and the rows the SQL of the relation-backed tables gives.
describe Wsjrdp::Filtering::ArrayCompiler do
  let(:row) { Struct.new(:id, :name, :note, :amount, :day, :kind, :ref, :ref2, keyword_init: true) }

  let(:source) do
    Wsjrdp::Filtering::ArraySource.define(:spec_rows) do |s|
      s.field :id, :integer
      s.field :name, :text
      s.field :note, :text
      s.field :amount, :numeric
      s.field :day, :date
      s.field :kind, :text
      s.field :ref, :integer
      s.field :ref2, :integer
    end
  end

  let(:schema) do
    Wsjrdp::Filtering::Schema.define do |s|
      text_ops = Fin::DatevBookingsFilterSchema::TEXT_OPERATORS
      s.attribute key: :name, label: "Name", type: Wsjrdp::Filtering::Types::TEXT, operators: text_ops,
        column: :name
      s.attribute key: :text, short_key: :tx, label: "Text", type: Wsjrdp::Filtering::Types::TEXT,
        operators: text_ops, column: ->(t) { [t[:name], t[:note]] }
      s.attribute key: :amount, short_key: :am, label: "Betrag", type: Wsjrdp::Filtering::Types::DECIMAL,
        operators: %i[eq gte gt lt lte between nonzero present blank], column: :amount
      s.attribute key: :day, short_key: :d, label: "Tag", type: Wsjrdp::Filtering::Types::DATE,
        operators: %i[gte lt lte between in_month in_year present blank], column: :day
      s.attribute key: :kind, short_key: :k, label: "Art", type: Wsjrdp::Filtering::Types::ENUM,
        operators: %i[in not_in], column: :kind,
        options: Wsjrdp::Filtering::Options.values(-> { [%w[a A], %w[b B]] })
      s.attribute key: :ref, short_key: :r, label: "Bezug", type: Wsjrdp::Filtering::Types::REFERENCE,
        operators: %i[in not_in present blank], column: ->(t) { [t[:ref], t[:ref2]] }
    end.bind(source)
  end

  let(:rows) do
    [
      row.new(id: 1, name: "Äpfel und Birnen", note: nil, amount: BigDecimal("10.5"), day: Date.new(2026, 1, 15),
        kind: "a", ref: 1, ref2: nil),
      row.new(id: 2, name: "apfel", note: "50% Rabatt", amount: BigDecimal(0), day: Date.new(2026, 2, 1),
        kind: "b", ref: nil, ref2: 2),
      row.new(id: 3, name: nil, note: "a_b\\c", amount: nil, day: nil, kind: nil, ref: nil, ref2: nil),
      row.new(id: 4, name: "RK-2026-0001", note: "Zeile1\nZeile2", amount: BigDecimal(-3), day: Date.new(2025, 12, 31),
        kind: "a", ref: 3, ref2: 3),
      row.new(id: 5, name: "Birne", note: "", amount: BigDecimal(1000), day: Date.new(2026, 1, 31), kind: "c",
        ref: 2, ref2: 9)
    ]
  end

  def ids(tree, strategy) = described_class.apply(Wsjrdp::Filtering::Query.parse(tree), rows, schema: schema,
    strategy: strategy).map(&:id)

  conditions = [
    ["name", "contains", "apfel"], ["name", "contains", "ÄPFEL"], ["name", "contains_cs", "apfel"],
    ["name", "not_contains", "apfel"], ["name", "not_contains_cs", "Birne"],
    ["name", "eq", "APFEL"], ["name", "eq_cs", "apfel"], ["name", "eq", "%"],
    ["name", "glob", "*birne*"], ["name", "glob", "rk-????-*"], ["name", "glob_cs", "B*"],
    ["name", "regex", "^rk-\\d{4}"], ["name", "regex_cs", "^RK"],
    ["text", "contains", "%"], ["text", "contains", "a_b"], ["text", "contains", "\\"], ["text", "glob", "*zeile2"],
    ["text", "not_contains", "apfel"], ["text", "eq", ""],
    ["amount", "eq", "0"], ["amount", "gte", "10,5"], ["amount", "gt", "10.5"], ["amount", "lt", "0"],
    ["amount", "lte", "0"], ["amount", "between", "-5", "11"], ["amount", "nonzero"], ["amount", "present"],
    ["amount", "blank"],
    ["day", "gte", "2026-01-15"], ["day", "lt", "2026-01-15"], ["day", "lte", "2026-01-31"],
    ["day", "between", "2026-01-01", "2026-01-31"], ["day", "in_month", "2026-01"], ["day", "in_year", "2025"],
    ["day", "present"], ["day", "blank"],
    ["kind", "in", "a", "c"], ["kind", "not_in", "a"],
    ["ref", "in", "2", "3"], ["ref", "not_in", "3"], ["ref", "present"], ["ref", "blank"]
  ]

  conditions.each do |condition|
    it "gives the same rows in Ruby and in SQL for #{condition.inspect}" do
      tree = [[condition]]

      expect(ids(tree, :ruby)).to eq(ids(tree, :sql))
    end
  end

  it "answers what SQL answers on NULLs, cases and the LIKE specials" do
    expect(ids([[%w[name contains ÄPFEL]]], :ruby)).to eq([1])
    expect(ids([[%w[name not_contains apfel]]], :ruby)).to eq([1, 3, 4, 5])
    expect(ids([[%w[kind not_in a]]], :ruby)).to eq([2, 5])
    expect(ids([[%w[ref not_in 3]]], :ruby)).to eq([5])
    expect(ids([[%w[text contains %]]], :ruby)).to eq([2])
    expect(ids([[["day", "in_month", "2026-01"]]], :ruby)).to eq([1, 5])
  end

  it "ANDs the slots, ORs within a slot and keeps the order of the rows" do
    tree = [[%w[kind in a], %w[amount gte 100]], [%w[day present]]]

    expect(ids(tree, :ruby)).to eq([1, 4, 5])
    expect(ids(tree, :sql)).to eq([1, 4, 5])
  end

  it "drops conditions it cannot use, like the relation compiler" do
    tree = [[%w[amount gte abc]], [%w[unknown eq x]], [["name", "contains"]]]

    expect(ids(tree, :ruby)).to eq([1, 2, 3, 4, 5])
    expect(ids(tree, :sql)).to eq([1, 2, 3, 4, 5])
  end

  it "answers no rows for no rows" do
    expect(described_class.apply(Wsjrdp::Filtering::Query.parse([[%w[kind in a]]]), [], schema: schema,
      strategy: :sql)).to eq([])
  end

  it "refuses an SQL expression for :ruby, which :sql handles" do
    expression = Wsjrdp::Filtering::Schema.define do |s|
      s.attribute key: :abs, label: "Betrag", type: Wsjrdp::Filtering::Types::DECIMAL, operators: %i[gte],
        column: ->(t) { Arel::Nodes::NamedFunction.new("ABS", [t[:amount]]) }
    end.bind(source)
    query = Wsjrdp::Filtering::Query.parse([[%w[abs gte 5]]])

    expect { described_class.apply(query, rows, schema: expression, strategy: :ruby) }
      .to raise_error(ArgumentError, /:sql/)
    expect(described_class.apply(query, rows, schema: expression, strategy: :sql).map(&:id)).to eq([1, 5])
  end

  it "takes the strategy from the settings unless the dataset names one" do
    allow(Settings.filtering).to receive(:array_strategy).and_return("sql")
    dataset = Module.new { extend Wsjrdp::Filtering::ArrayFilterSchema }

    expect(dataset.array_strategy).to eq(:sql)
    expect { described_class.for(:fast) }.to raise_error(ArgumentError)
  end

  it "filters through the filter schema protocol" do
    bound = schema
    dataset = Module.new do
      extend Wsjrdp::Filtering::ArrayFilterSchema
      define_singleton_method(:array_strategy) { :ruby }
    end
    query = dataset.decode(dataset.encode(Wsjrdp::Filtering::Query.parse([[%w[kind in b]]]), schema: bound),
      schema: bound)

    expect(dataset.compile(query, schema: bound, relation: rows).map(&:id)).to eq([2])
  end
end
