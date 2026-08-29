# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Kreditoren filter schema (Fin::PersonalAccountsFilterSchema) compiled
# against the REAL relation it is bound to
# (WsjrdpPersonalAccount.with_booking_summary): the two aggregate columns, the
# COALESCEd Moss status and the text search over both name columns. The generic
# engine is covered standalone in spec/domain/wsjrdp/filtering_engine_spec.rb.
describe Fin::PersonalAccountsFilterSchema do
  let(:schema) { described_class.bound }

  # Numbers are invented (the table's CHECK constraints want six digits, a
  # creditor starting 7-9).
  def account(number, name: nil, short_name: nil, moss_status: "active")
    WsjrdpPersonalAccount.create!(number: number, name: name, short_name: short_name,
      account_kind: "CREDITOR", moss_status: moss_status)
  end

  # One booking whose KONTO is the creditor, so its leg is +amount for "D" and
  # -amount for "C" (see doc/fin/money_conventions.md).
  def booking(number, amount, debit_credit: "D")
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: number, account_kind: "CREDITOR",
      offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
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
      account("700101", name: "Alpha Werkstatt")     # 2 bookings, balance 30
      account("700102", name: "Beta Handel")         # 1 booking, balance -50
      account("700103", name: "Gamma GmbH")          # 1 booking, balance 0 (D + C)
      account("700104", name: "Delta AG")            # no booking at all
      booking("700101", 100)
      booking("700101", 70, debit_credit: "C")
      booking("700102", 50, debit_credit: "C")
      booking("700103", 20)
      booking("700103", 20, debit_credit: "C")
    end

    it "gives every account its two-sided balance and count, zero when it has none" do
      rows = WsjrdpPersonalAccount.with_booking_summary
        .pluck(:number, :booking_balance, :booking_count).sort
      expect(rows).to eq([["700101", 30, 2], ["700102", -50, 1],
        ["700103", 0, 2], ["700104", 0, 0]])
    end

    it "filters on the count with the strict >" do
      expect(numbers([[["booking_count", "gt", 0]]])).to eq(%w[700101 700102 700103])
      expect(numbers([[["booking_count", "gt", 1]]])).to eq(%w[700101 700103])
    end

    # `≠ 0` is what a count is asked for first ("has bookings at all"), so it
    # leads the list and is the operator a fresh condition starts on.
    it "asks a count for ≠ 0 without an operand" do
      expect(numbers([[["booking_count", "nonzero"]]])).to eq(%w[700101 700102 700103])
      expect(schema.find(:booking_count).operators.map(&:key))
        .to eq(%i[nonzero between lte gte lt gt eq])
      expect(schema.find(:booking_count).pickable_operators.map(&:key))
        .to eq(%i[nonzero between lte gte lt gt eq])
      expect(schema.find(:booking_count).sign).to be_nil
    end

    it "filters on the balance, ranges and both sides of zero" do
      expect(numbers([[["booking_balance", "gt", 0], ["booking_balance", "lt", 0]]]))
        .to eq(%w[700101 700102])
      expect(numbers([[["booking_balance", "between", -60, -10]]])).to eq(%w[700102])
      expect(numbers([[["booking_balance", "eq", 0]]])).to eq(%w[700103 700104])
      expect(numbers([[["booking_balance", "gte", 30]]])).to eq(%w[700101])
      expect(numbers([[["booking_balance", "lte", -50]]])).to eq(%w[700102])
    end

    # |Saldo| is the default variant because a creditor's balance is negative as
    # often as positive: the magnitude asks "how much", the signed one "which
    # side". `≠ 0` is the operand-less "has a balance at all".
    it "sees both signs through |Saldo|, one through Saldo" do
      expect(numbers([[["booking_balance_abs", "nonzero"]]])).to eq(%w[700101 700102])
      expect(numbers([[["booking_balance_abs", "gte", 30]]])).to eq(%w[700101 700102])
      expect(numbers([[["booking_balance", "gte", 30]]])).to eq(%w[700101])
      expect(numbers([[["booking_balance_abs", "between", 40, 60]]])).to eq(%w[700102])
      expect(apply([[["booking_balance_abs", "gte", 30]]]).to_sql)
        .to include(%(ABS("wsjrdp_personal_accounts"."booking_balance") >= 30))
    end

    it "ANDs two slots, so a preset's slots narrow each other" do
      expect(numbers([[["booking_count", "gt", 0]], [["booking_balance", "gt", 0]]]))
        .to eq(%w[700101])
    end

    it "searches both name columns case-insensitively" do
      account("700105", name: nil, short_name: "Alpha kurz")
      expect(numbers([[["name", "contains", "alpha"]]])).to eq(%w[700101 700105])
      expect(numbers([[["name", "eq", "Beta Handel"]]])).to eq(%w[700102])
      expect(numbers([[["name", "contains", "nichts davon"]]])).to eq([])
    end
  end

  # The user decision behind the ENUM: Moss knows an account as active or
  # deactivated, and an account it does not know at all (NULL) counts as
  # INAKTIV -- in the filter exactly as in the cell and the sort.
  describe "the Moss status" do
    before do
      account("700201", moss_status: "active")
      account("700202", moss_status: "deactivated")
      account("700203", moss_status: nil)
    end

    it "counts a NULL status as deactivated" do
      expect(numbers([[["moss_status", "in", "deactivated"]]])).to eq(%w[700202 700203])
      expect(numbers([[["moss_status", "in", "active"]]])).to eq(%w[700201])
    end

    it "negates over the same COALESCE, so no row falls through the gap" do
      expect(numbers([[["moss_status", "not_in", "active"]]])).to eq(%w[700202 700203])
    end

    it "offers exactly the two options, labelled aktiv and inaktiv" do
      options = schema.find(:moss_status).options.pairs
      expect(options).to eq([["active", "aktiv"], ["deactivated", "inaktiv"]])
    end
  end

  describe "the catalog and the wire form" do
    it "offers the filterable attributes with their short keys" do
      expect(schema.catalog[:attributes].pluck(:key))
        .to eq(%i[name booking_balance_abs booking_balance booking_count moss_status])
      expect(schema.attributes.values.map(&:short_key)).to eq(%i[q bba bb bc ms])
    end

    # The two Saldo attributes are ONE picker entry with a sign toggle; |Saldo|
    # is declared first and is therefore the group's default. Both offer the
    # whole comparison set, `≠ 0` first.
    it "pairs |Saldo| and Saldo in one variant group, magnitude first" do
      magnitude = schema.find(:booking_balance_abs)
      signed = schema.find(:booking_balance)
      expect([magnitude.variant_group, signed.variant_group]).to eq(%w[Saldo Saldo])
      expect([magnitude.label, signed.label]).to eq(["|Saldo|", "Saldo"])
      expect([magnitude.sign, signed.sign]).to eq(%i[absolute signed])
      expect([magnitude.operand_min, signed.operand_min]).to eq([0, nil])
      expect(magnitude.operators.map(&:key)).to eq(%i[nonzero between lte gte lt gt eq])
      expect(magnitude.pickable_operators.map(&:key)).to eq(%i[nonzero between lte gte lt gt eq])
      expect(signed.pickable_operators.map(&:key)).to eq(%i[nonzero between lte gte lt gt eq])
      expect(magnitude.operators.map(&:label))
        .to eq(["≠ 0", "im Bereich", "≤", "≥", "<", ">", "="])
    end

    # The sign metadata reaches the builder through the catalog -- that is what
    # turns the group's sub-variant dropdown into the ± / |x| toggle.
    it "ships the sign of both members in the catalog" do
      balances = schema.catalog[:attributes].select { |a| a[:variant_group] == "Saldo" }
      expect(balances.pluck(:key)).to eq(%i[booking_balance_abs booking_balance])
      expect(balances.pluck(:sign)).to eq(%i[absolute signed])
    end

    it "round-trips the ≠ 0 preset condition through the short-key wire form" do
      query = described_class.parse_fixed!([[["booking_balance_abs", "nonzero"]]], schema: schema)
      wire = described_class.encode(query, schema: schema)
      expect(wire).to eq("!(!(!(bba,nz)))")
      expect(described_class.decode(wire, schema: schema).as_json)
        .to eq([[["booking_balance_abs", "nonzero"]]])
      # The signed variant on the wire, with its own short key and operator.
      expect(described_class.decode("!(!(!(bb,lt,0)))", schema: schema).as_json)
        .to eq([[["booking_balance", "lt", 0]]])
    end

    it "round-trips a condition through the short-key wire form" do
      query = Wsjrdp::Filtering::Query.parse([[["booking_count", "gt", 0]]])
      wire = described_class.encode(query, schema: schema)
      expect(wire).to eq("!(!(!(bc,gt,0)))")
      expect(described_class.decode(wire, schema: schema).as_json)
        .to eq([[["booking_count", "gt", 0]]])
    end

    it "parses a host-pinned tree strictly and compiles it onto the relation" do
      account("700301", moss_status: "active")
      account("700302", moss_status: "deactivated")
      query = described_class.parse_fixed!([[["moss_status", "in", "active"]]], schema: schema)
      scope = described_class.compile(query, schema: schema, relation: WsjrdpPersonalAccount.all)
      expect(scope.pluck(:number)).to eq(%w[700301])
    end

    it "raises for an unknown attribute and for an operator the attribute lacks" do
      expect { described_class.parse_fixed!([[["typo", "in", "x"]]], schema: schema) }
        .to raise_error(ArgumentError, /unknown attribute "typo"/)
      expect { described_class.parse_fixed!([[["moss_status", "gt", 1]]], schema: schema) }
        .to raise_error(ArgumentError, /does not offer operator "gt"/)
    end
  end
end
