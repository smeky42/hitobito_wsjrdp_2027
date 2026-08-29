# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Sachkonten filter schema (Fin::LedgerAccountsFilterSchema) compiled against
# the REAL relation it is bound to (WsjrdpLedgerAccount.with_booking_summary):
# the two-sided aggregate columns, the text search over both name columns and the
# Kontoart enum. The generic engine is covered standalone in
# spec/domain/wsjrdp/filtering_engine_spec.rb.
describe Fin::LedgerAccountsFilterSchema do
  let(:schema) { described_class.bound }

  # Invented numbers and names. Six-digit numbers starting with 1-9 are
  # Personenkonten and barred from this table by a CHECK constraint.
  def account(number, name: nil, short_name: nil, account_kind: "EXPENSE", moss_status: nil)
    WsjrdpLedgerAccount.create!(number: number, name: name, short_name: short_name,
      account_kind: account_kind, moss_status: moss_status, visibility: "visible")
  end

  # The Konto is a BANK account, so signed_base_amount is +amount for "D" and
  # -amount for "C"; the Gegenkonto's own leg carries the opposite direction and,
  # for an INCOME/EXPENSE account, the sign flip of that account type (see
  # doc/fin/money_conventions.md).
  def booking(account_number, offsetting_number, amount, debit_credit: "D",
    offsetting_kind: "EXPENSE")
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: account_number, account_kind: "BANK",
      offsetting_account_number: offsetting_number, offsetting_account_kind: offsetting_kind,
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
      account("1200", name: "Alpha Bank", account_kind: "BANK")
      account("4000", name: "Beta Erloese", account_kind: "INCOME")
      account("66500", name: "Gamma Aufwand")
      account("9000", name: "Delta Kapital", account_kind: "EQUITY")
      booking("1200", "66500", 100)
      booking("1200", "4000", 300, debit_credit: "C", offsetting_kind: "INCOME")
    end

    # A Sachkonto appears as Gegenkonto as readily as as Konto, so the totals
    # come from DatevBooking.legs -- each side valued from its own perspective.
    it "gives every account its two-sided sum and count, zero when it has none" do
      rows = WsjrdpLedgerAccount.with_booking_summary
        .pluck(:number, :booking_sum, :booking_count).sort
      expect(rows).to eq([["1200", -200, 2], ["4000", -300, 1],
        ["66500", 100, 1], ["9000", 0, 0]])
    end

    # A booking whose account has no master record of its own is simply not a row
    # here -- the list is the MASTER DATA, joined with its totals.
    it "ignores an account number that only ever appears on a booking" do
      booking("1200", "77000", 10)
      expect(numbers([[["name", "contains", "a"]]])).to eq(%w[1200 4000 66500 9000])
    end
  end

  describe "the name search" do
    before do
      account("1200", name: "Alpha Bank", short_name: "Alpha")
      account("4000", name: "Beta Erloese", short_name: nil)
      account("66500", name: nil, short_name: "Gamma kurz")
    end

    # ONE attribute over two columns: a positive predicate matches in EITHER.
    it "hits the Bezeichnung OR the Kurzbezeichnung" do
      expect(numbers([[["name", "contains", "erloese"]]])).to eq(%w[4000])
      expect(numbers([[["name", "contains", "kurz"]]])).to eq(%w[66500])
      expect(numbers([[["name", "contains", "alpha"]]])).to eq(%w[1200])
      expect(numbers([[["name", "eq", "Beta Erloese"]]])).to eq(%w[4000])
      expect(numbers([[["name", "contains", "nichts davon"]]])).to eq([])
    end

    # The glob pair the Buchungen page offers is part of the list here too: a
    # whole-value match with * and ?, which is what one reaches for on a name.
    it "offers the glob operators, matching the WHOLE value" do
      expect(numbers([[["name", "glob", "Alpha*"]]])).to eq(%w[1200])
      expect(numbers([[["name", "glob", "*kurz"]]])).to eq(%w[66500])
      expect(numbers([[["name", "glob", "Alpha"]]])).to eq(%w[1200]) # the short name is exactly it
    end

    # "enthält nicht" requires NO column to match, and a NULL column counts as
    # empty there -- so an account without a Bezeichnung does not fall out.
    it "negates over both columns, NULL counting as empty" do
      expect(numbers([[["name", "not_contains", "alpha"]]])).to eq(%w[4000 66500])
    end
  end

  # The Kontoart is the DATEV Kontenart short code the chart export brings; the
  # picker offers it under the German label of fin.account_kind.*.
  describe "the Kontoart" do
    before do
      account("1200", account_kind: "BANK")
      account("4000", account_kind: "INCOME")
      account("66500", account_kind: "EXPENSE")
    end

    it "narrows on the code, positively and negatively" do
      expect(numbers([[["account_kind", "in", "BANK"]]])).to eq(%w[1200])
      expect(numbers([[["account_kind", "in", "BANK", "INCOME"]]])).to eq(%w[1200 4000])
      expect(numbers([[["account_kind", "not_in", "BANK"]]])).to eq(%w[4000 66500])
    end

    it "offers the kinds of the master data, labelled in German" do
      expect(schema.find(:account_kind).options.pairs)
        .to eq([["BANK", "Bank"], ["EXPENSE", "Aufwand"], ["INCOME", "Ertrag"]])
    end
  end

  # The user decision behind the ENUM: Moss knows an account as active or
  # deactivated, and one it does not know at all (NULL) counts as INAKTIV -- in
  # the filter exactly as in the cell and the sort.
  describe "the Moss status" do
    before do
      account("1210", moss_status: "active")
      account("1220", moss_status: "deactivated")
      account("1230", moss_status: nil)
    end

    it "counts a NULL status as deactivated" do
      expect(numbers([[["moss_status", "in", "deactivated"]]])).to eq(%w[1220 1230])
      expect(numbers([[["moss_status", "in", "active"]]])).to eq(%w[1210])
    end

    it "negates over the same COALESCE, so no row falls through the gap" do
      expect(numbers([[["moss_status", "not_in", "active"]]])).to eq(%w[1220 1230])
    end

    it "offers exactly the two options, labelled aktiv and inaktiv" do
      options = schema.find(:moss_status).options.pairs
      expect(options).to eq([["active", "aktiv"], ["deactivated", "inaktiv"]])
    end
  end

  describe "the catalog and the wire form" do
    it "offers the filterable attributes with their short keys" do
      expect(schema.attributes.keys).to eq(%i[name account_kind moss_status])
      expect(schema.attributes.values.map(&:short_key)).to eq(%i[q ak ms])
      expect(schema.catalog[:attributes].pluck(:key)).to eq(%i[name account_kind moss_status])
    end

    it "round-trips a Kontoart condition through the short-key wire form" do
      query = described_class.parse_fixed!([[["account_kind", "in", "BANK"]]], schema: schema)
      wire = described_class.encode(query, schema: schema)
      expect(wire).to eq("!(!(!(ak,in,'BANK')))")
      expect(described_class.decode(wire, schema: schema).as_json)
        .to eq([[["account_kind", "in", "BANK"]]])
    end

    it "raises for an unknown attribute and for an operator the attribute lacks" do
      expect { described_class.parse_fixed!([[["typo", "in", "x"]]], schema: schema) }
        .to raise_error(ArgumentError, /unknown attribute "typo"/)
      expect { described_class.parse_fixed!([[["account_kind", "gt", 1]]], schema: schema) }
        .to raise_error(ArgumentError, /does not offer operator "gt"/)
    end
  end
end
