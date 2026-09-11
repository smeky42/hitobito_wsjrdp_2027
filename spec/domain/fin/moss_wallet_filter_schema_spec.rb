# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Moss WALLET filter schema (Fin::MossWalletFilterSchema) compiled against
# the relation it is bound to, MossBooking joined to its transaction. The grain
# is what separates it from Fin::MossTransactionsFilterSchema: a row here is a
# SPLIT, so `kind` and `booking_date` reach through the join while `amount` is
# the booking's own column. The generic engine is covered standalone in
# spec/domain/wsjrdp/filtering_engine_spec.rb.
#
# One booking per kind, all invented; their dates, amounts and texts differ so
# each attribute selects a different subset.
describe Fin::MossWalletFilterSchema do
  let(:schema) { described_class.bound }

  # One transaction of `type` with its (shell) expense and exactly one booking.
  def create_booking(type, amount:, date:, transaction_text:, booking_text:, **attrs)
    uuid = SecureRandom.uuid
    transaction = MossTransaction.create!(type: type, moss_transaction_uuid: uuid,
      signed_total_base_amount: amount, currency: "EUR", booking_date: date,
      transaction_posting_text: transaction_text, **attrs)
    expense = MossExpense.create!(moss_transaction: transaction, moss_expense_uuid: uuid,
      type: "#{type}Expense", expense_number: 1, signed_expense_base_amount: amount)
    MossBooking.create!(moss_transaction: transaction, moss_expense: expense,
      sub_row_number: 1, signed_base_amount: amount, booking_posting_text: booking_text)
  end

  before do
    create_booking("MossCardTransaction", amount: -25, date: Date.new(2026, 5, 3),
      transaction_text: "Verpflegung Vortreffen", booking_text: "Split eins")
    create_booking("MossReimbursement", amount: -60, date: Date.new(2026, 6, 1),
      transaction_text: "Reisekosten", booking_text: "Anteil eins")
    create_booking("MossInvoice", amount: -100, date: Date.new(2026, 7, 15),
      transaction_text: "Materiallieferung", booking_text: "Zeile eins")
    create_booking("MossTopUp", amount: 500, date: Date.new(2027, 1, 20),
      transaction_text: "", booking_text: "Aufladung")
  end

  def apply(tree)
    Wsjrdp::Filtering::Compiler.new(schema)
      .apply(Wsjrdp::Filtering::Query.parse(tree))
  end

  # The kinds of the bookings a tree selects, in the schema's own kind order.
  def kinds(tree)
    order = Fin::MossTransactionsFilterSchema::KINDS
    apply(tree).map { |b| b.moss_transaction.type }.sort_by { |type| order.index(type) }
  end

  describe "the base relation" do
    it "lists bookings, joined to their transaction" do
      expect(schema.base.klass).to eq(MossBooking)
      expect(schema.base.to_sql).to include('INNER JOIN "moss_transactions"')
      expect(schema.base.count).to eq(4)
    end

    # The host hands in its own relation; #compile merges the base into it, so
    # the join is never repeated (the wallet page adds only its account).
    it "merges its join into a host relation instead of asking for it twice" do
      scope = described_class.compile(nil, schema: schema, relation: MossBooking.all)
      expect(scope.to_sql.scan('INNER JOIN "moss_transactions"').size).to eq(1)
      expect(scope.count).to eq(4)
    end
  end

  describe "the kind (Art)" do
    it "selects and excludes on the transaction's STI type" do
      expect(kinds([[["kind", "in", "MossInvoice"]]])).to eq(%w[MossInvoice])
      expect(kinds([[["kind", "not_in", "MossTopUp"]]]))
        .to eq(%w[MossCardTransaction MossReimbursement MossInvoice])
    end

    it "ORs several kinds inside one slot" do
      expect(kinds([[["kind", "in", "MossCardTransaction"], ["kind", "in", "MossTopUp"]]]))
        .to eq(%w[MossCardTransaction MossTopUp])
    end

    it "compiles onto moss_transactions.type, not onto the booking" do
      expect(apply([[["kind", "in", "MossInvoice"]]]).to_sql)
        .to include('"moss_transactions"."type"')
    end

    # The words and values are literally the Moss section's, so "Rechnung"
    # means the same thing in both pickers.
    it "offers exactly the Moss section's four kinds" do
      pairs = schema.find(:kind).options.pairs
      expect(pairs).to eq(Fin::MossTransactionsFilterSchema::KIND_OPTIONS.pairs)
      expect(pairs).to eq(Fin::MossTransactionsFilterSchema::KINDS
        .map { |kind| [kind, I18n.t("fin.moss.kinds.#{kind}")] })
    end
  end

  describe "the other attributes" do
    # The booking has no date of its own; Buchungsdatum is the transaction's
    # booking_date, the column the table shows and sorts by as well.
    it "filters on Buchungsdatum through the join" do
      expect(kinds([[["booking_date", "gte", "2026-07-01"]]])).to eq(%w[MossInvoice MossTopUp])
      expect(kinds([[["booking_date", "lt", "2026-06-01"]]])).to eq(%w[MossCardTransaction])
      expect(kinds([[["booking_date", "between", "2026-05-04", "2026-07-31"]]]))
        .to eq(%w[MossReimbursement MossInvoice])
      expect(kinds([[["booking_date", "in_year", "2027"]]])).to eq(%w[MossTopUp])
      expect(apply([[["booking_date", "in_year", "2027"]]]).to_sql)
        .to include('"moss_transactions"."booking_date"')
    end

    # Betrag is the SPLIT's signed EUR share -- what the row shows and what the
    # wallet balance is the sum of.
    it "filters on the booking's own signed amount" do
      expect(kinds([[["amount", "gte", 0]]])).to eq(%w[MossTopUp])
      expect(kinds([[["amount", "lt", -50]]])).to eq(%w[MossReimbursement MossInvoice])
      expect(kinds([[["amount", "between", -60, -25]]]))
        .to eq(%w[MossCardTransaction MossReimbursement])
      expect(kinds([[["amount", "eq", 500]]])).to eq(%w[MossTopUp])
      expect(apply([[["amount", "gte", 0]]]).to_sql).to include('"moss_bookings"."signed_base_amount"')
    end

    # The magnitude of the same column: money leaves the wallet as a negative
    # amount, so only |Betrag| sees both directions at once.
    it "sees both directions through |Betrag|" do
      expect(kinds([[["amount_abs", "gte", 100]]])).to eq(%w[MossInvoice MossTopUp])
      expect(kinds([[["amount_abs", "between", 25, 60]]]))
        .to eq(%w[MossCardTransaction MossReimbursement])
      expect(kinds([[["amount", "gte", 100]]])).to eq(%w[MossTopUp])
      expect(apply([[["amount_abs", "gte", 100]]]).to_sql)
        .to include(%(ABS("moss_bookings"."signed_base_amount") >= 100))
    end

    # One search over the two Buchungstexte the row renders; a positive
    # predicate matches in EITHER.
    it "searches the split's text and the payment's alike" do
      expect(kinds([[["text", "contains", "anteil"]]])).to eq(%w[MossReimbursement])
      expect(kinds([[["text", "contains", "vortreffen"]]])).to eq(%w[MossCardTransaction])
      expect(kinds([[["text", "contains", "eins"]]]))
        .to eq(%w[MossCardTransaction MossReimbursement MossInvoice])
      expect(kinds([[["text", "contains", "nichts davon"]]])).to eq([])
    end
  end

  describe "the catalog and the wire form" do
    it "offers the four attributes with their short keys" do
      expect(schema.catalog[:attributes].pluck(:key))
        .to eq(%i[kind booking_date amount amount_abs text])
      expect(schema.attributes.values.map(&:short_key)).to eq(%i[k bd amt amta q])
      expect(schema.find(:kind).operators.map(&:key)).to eq(%i[in not_in])
      # The same column, the same words and the same operators as the Moss
      # section's Buchungsdatum.
      expect(schema.find(:booking_date).operators.map(&:key))
        .to eq(Fin::MossTransactionsFilterSchema::NULLABLE_DATE_OPERATORS)
    end

    # Betrag is ONE picker entry with a sign toggle, the signed member first
    # (= the group's default); both offer the Moss section's operator list.
    it "pairs Betrag and |Betrag| in one variant group, signed first" do
      signed = schema.find(:amount)
      magnitude = schema.find(:amount_abs)
      expect([signed.variant_group, magnitude.variant_group]).to eq(%w[Betrag Betrag])
      expect([signed.label, magnitude.label]).to eq(["Betrag", "|Betrag|"])
      expect([signed.sign, magnitude.sign]).to eq(%i[signed absolute])
      expect([signed.operand_min, magnitude.operand_min]).to eq([nil, 0])
      expect(signed.operators.map(&:key)).to eq(%i[between lte gte lt gt eq])
      expect(magnitude.operators.map(&:key)).to eq(%i[between lte gte lt gt eq])
      expect(schema.catalog[:attributes].select { |a| a[:variant_group] == "Betrag" }
        .pluck(:sign)).to eq(%i[signed absolute])
    end

    it "round-trips a kind condition through the short-key wire form" do
      query = Wsjrdp::Filtering::Query.parse([[["kind", "in", "MossTopUp"]]])
      expect(described_class.encode(query, schema: schema)).to eq("!(!(!(k,in,'MossTopUp')))")
      expect(described_class.decode("!(!(!(k,in,'MossTopUp')))", schema: schema).as_json)
        .to eq([[["kind", "in", "MossTopUp"]]])
    end
  end

  # The wallet's "Schnellauswahl" is four host-authored slots, one per kind.
  # They are parsed STRICTLY, so a typo raises here instead of silently
  # widening the page to every kind.
  describe "the four kind presets" do
    let(:preset_slots) do
      Fin::MossTransactionsFilterSchema::KINDS.map { |kind| [[["kind", "in", kind]]] }
    end

    it "accepts every preset's slots and compiles each to its own kind" do
      preset_slots.each do |slots|
        query = described_class.parse_fixed!(slots, schema: schema)
        kind = slots.dig(0, 0, 2)
        scope = described_class.compile(query, schema: schema, relation: MossBooking.all)
        expect(scope.map { |b| b.moss_transaction.type }).to eq([kind])
      end
    end

    # Fin::WsjrdpFinAccountsController#wallet_presets declares the kinds as ONE
    # preset group ("kind" in <value>); every member's value is one of these
    # slots, in the same order.
    it "is exactly what the controller's preset group declares" do
      group = Fin::WsjrdpFinAccountsController.new.send(:wallet_presets).sole
      expect(group).to include(group: "kind", attribute: "kind", operator: "in")
      member_slots = group[:members].map { |member| [[["kind", "in", member[:value]]]] }
      expect(member_slots).to eq(preset_slots)
    end

    it "raises for an attribute or an operator the schema does not have" do
      expect { described_class.parse_fixed!([[["knd", "in", "MossTopUp"]]], schema: schema) }
        .to raise_error(ArgumentError, /unknown attribute "knd"/)
      expect { described_class.parse_fixed!([[["kind", "contains", "Moss"]]], schema: schema) }
        .to raise_error(ArgumentError, /does not offer operator "contains"/)
    end
  end
end
