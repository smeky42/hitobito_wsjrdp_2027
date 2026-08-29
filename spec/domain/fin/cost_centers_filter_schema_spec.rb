# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Kostenstellen filter schema (Fin::CostCentersFilterSchema) compiled against
# the REAL relation it is bound to (WsjrdpCostCenter.with_booking_summary): the
# two aggregate columns, the COALESCEd Moss status, the text search over both
# name columns and the catalog-less `number` the page's hidden fixed slot uses.
# The generic engine is covered standalone in
# spec/domain/wsjrdp/filtering_engine_spec.rb.
describe Fin::CostCentersFilterSchema do
  let(:schema) { described_class.bound }

  # Numbers and names are invented; cost-center numbers may contain letters.
  def cost_center(number, name: nil, short_name: nil, moss_status: "active")
    WsjrdpCostCenter.create!(number: number, name: name, short_name: short_name,
      moss_status: moss_status)
  end

  # The Konto is a BANK account, so signed_base_amount is +amount for "D" and
  # -amount for "C" (see doc/fin/money_conventions.md).
  def booking(cost_center_number, amount, debit_credit: "D")
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
      cost_center_number: cost_center_number,
      base_amount: amount, transaction_amount: amount, debit_credit: debit_credit,
      base_currency: "EUR", booking_date: Date.new(2026, 2, 1))
  end

  def apply(tree)
    Wsjrdp::Filtering::Compiler.new(schema)
      .apply(Wsjrdp::Filtering::Query.parse(tree))
  end

  def numbers(tree) = apply(tree).pluck(:number).sort

  describe "the booking aggregates" do
    before do
      cost_center("K100", name: "Alpha Lager")   # 2 bookings, sum 30
      cost_center("K200", name: "Beta Zelte")    # 1 booking, sum -50
      cost_center("K300", name: "Gamma Küche")   # 2 bookings, sum 0 (D + C)
      cost_center("K400", name: "Delta Depot")   # no booking at all
      booking("K100", 100)
      booking("K100", 70, debit_credit: "C")
      booking("K200", 50, debit_credit: "C")
      booking("K300", 20)
      booking("K300", 20, debit_credit: "C")
    end

    it "gives every cost center its sum and count, zero when it has none" do
      rows = WsjrdpCostCenter.with_booking_summary
        .pluck(:number, :booking_sum, :booking_count).sort
      expect(rows).to eq([["K100", 30, 2], ["K200", -50, 1],
        ["K300", 0, 2], ["K400", 0, 0]])
    end

    # A booking whose cost center has no master record of its own is simply not
    # a row here -- the list is the MASTER DATA, joined with its totals.
    it "ignores a cost-center number that only ever appears on a booking" do
      booking("K999", 10)
      expect(numbers([[["booking_count", "nonzero"]]])).to eq(%w[K100 K200 K300])
    end

    it "filters on the count, with ≠ 0 and with the comparisons" do
      expect(numbers([[["booking_count", "nonzero"]]])).to eq(%w[K100 K200 K300])
      expect(numbers([[["booking_count", "gt", 1]]])).to eq(%w[K100 K300])
      expect(numbers([[["booking_count", "eq", 0]]])).to eq(%w[K400])
      expect(numbers([[["booking_count", "between", 1, 1]]])).to eq(%w[K200])
    end

    it "ANDs two slots, so a preset's slot narrows a user's" do
      expect(numbers([[["booking_count", "nonzero"]], [["name", "contains", "a"]]]))
        .to eq(%w[K100 K200 K300])
    end
  end

  describe "the name search" do
    before do
      cost_center("K100", name: "Alpha Lager", short_name: "Alpha")
      cost_center("K200", name: "Beta Zelte", short_name: nil)
      cost_center("K300", name: nil, short_name: "Gamma kurz")
    end

    # ONE attribute over two columns: a positive predicate matches in EITHER.
    it "hits the Bezeichnung OR the Kurzbezeichnung" do
      expect(numbers([[["name", "contains", "zelte"]]])).to eq(%w[K200])
      expect(numbers([[["name", "contains", "kurz"]]])).to eq(%w[K300])
      expect(numbers([[["name", "contains", "alpha"]]])).to eq(%w[K100])
      expect(numbers([[["name", "eq", "Beta Zelte"]]])).to eq(%w[K200])
      expect(numbers([[["name", "contains", "nichts davon"]]])).to eq([])
    end

    # The glob pair the Buchungen page offers is part of the list here too: a
    # whole-value match with * and ?, which is what one reaches for on a name.
    it "offers the glob operators, matching the WHOLE value" do
      expect(numbers([[["name", "glob", "Alpha*"]]])).to eq(%w[K100])
      expect(numbers([[["name", "glob", "*kurz"]]])).to eq(%w[K300])
      expect(numbers([[["name", "glob", "Alpha"]]])).to eq(%w[K100]) # the short name is exactly it
    end

    # "enthält nicht" requires NO column to match, and a NULL column counts as
    # empty there -- so a cost center without a Bezeichnung does not fall out.
    it "negates over both columns, NULL counting as empty" do
      expect(numbers([[["name", "not_contains", "alpha"]]])).to eq(%w[K200 K300])
    end
  end

  # The user decision behind the ENUM: Moss knows a cost center as active or
  # deactivated, and one it does not know at all (NULL) counts as INAKTIV -- in
  # the filter exactly as in the cell and the sort.
  describe "the Moss status" do
    before do
      cost_center("K510", moss_status: "active")
      cost_center("K520", moss_status: "deactivated")
      cost_center("K530", moss_status: nil)
    end

    it "counts a NULL status as deactivated" do
      expect(numbers([[["moss_status", "in", "deactivated"]]])).to eq(%w[K520 K530])
      expect(numbers([[["moss_status", "in", "active"]]])).to eq(%w[K510])
    end

    it "negates over the same COALESCE, so no row falls through the gap" do
      expect(numbers([[["moss_status", "not_in", "active"]]])).to eq(%w[K520 K530])
    end

    it "offers exactly the two options, labelled aktiv and inaktiv" do
      options = schema.find(:moss_status).options.pairs
      expect(options).to eq([["active", "aktiv"], ["deactivated", "inaktiv"]])
    end
  end

  # `number` is declared for COMPILATION only (catalog: false): it exists so the
  # page can pin a cost center out of its list, not so a user can filter by it.
  describe "the pinning attribute" do
    before do
      cost_center("K100", name: "Alpha Lager")
      cost_center("K200", name: "Beta Zelte")
      cost_center("9", name: "Platzhalter")
    end

    it "stays out of the picker while remaining compilable" do
      expect(schema.catalog[:attributes].pluck(:key)).to eq(%i[name moss_status booking_count])
      expect(schema.find(:number)).to be_present
    end

    it "compiles the page's fixed slot to a NOT IN and drops that cost center" do
      query = described_class.parse_fixed!(
        [[["number", "not_in", Fin::CostCentersController::HIDDEN_COST_CENTER_NUMBER]]],
        schema: schema
      )
      scope = described_class.compile(query, schema: schema, relation: WsjrdpCostCenter.all)
      expect(scope.to_sql).to include(%("wsjrdp_cost_centers"."number" NOT IN ('9')))
      expect(scope.pluck(:number).sort).to eq(%w[K100 K200])
    end
  end

  describe "the catalog and the wire form" do
    it "offers the filterable attributes with their short keys" do
      expect(schema.attributes.keys).to eq(%i[name moss_status booking_count number])
      expect(schema.attributes.values.map(&:short_key)).to eq(%i[q ms bc nr])
    end

    it "round-trips the ≠ 0 preset condition through the short-key wire form" do
      query = described_class.parse_fixed!([[["booking_count", "nonzero"]]], schema: schema)
      wire = described_class.encode(query, schema: schema)
      expect(wire).to eq("!(!(!(bc,nz)))")
      expect(described_class.decode(wire, schema: schema).as_json)
        .to eq([[["booking_count", "nonzero"]]])
    end

    it "raises for an unknown attribute and for an operator the attribute lacks" do
      expect { described_class.parse_fixed!([[["typo", "in", "x"]]], schema: schema) }
        .to raise_error(ArgumentError, /unknown attribute "typo"/)
      expect { described_class.parse_fixed!([[["moss_status", "gt", 1]]], schema: schema) }
        .to raise_error(ArgumentError, /does not offer operator "gt"/)
    end
  end
end
