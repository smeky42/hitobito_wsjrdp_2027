# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The bookings filter schema (Fin::DatevBookingsFilterSchema) together with the parts
# of the generic CNF engine (doc/wsjrdp/generic_filter_builder.md) that need
# Rails: the Arel compiler (3VL, neutral-on-invalid, the batch join) and
# derive/bind against a real relation. The engine itself -- vocabulary, value
# objects, schema definition, URL codec, catalog projection -- is covered
# standalone in spec/domain/wsjrdp/filtering_engine_spec.rb.
describe Fin::DatevBookingsFilterSchema do
  let(:schema) { Fin::DatevBookingsFilterSchema.bound }

  def booking(attrs)
    defaults = {base_currency: "EUR",
                base_amount: 10, debit_credit: "D",
                account_number: "18000", offsetting_account_number: "66500",
                account_kind: "BANK", offsetting_account_kind: "EXPENSE",
                booking_date: Date.new(2026, 1, 15)}
    attrs = defaults.merge(attrs)
    attrs[:transaction_amount] ||= attrs[:base_amount]
    attrs[:buchungs_guid] ||= SecureRandom.uuid
    DatevBooking.create!(attrs)
  end

  describe Wsjrdp::Filtering::Compiler do
    def apply(tree)
      described_class.new(schema).apply(Wsjrdp::Filtering::Query.parse(tree))
    end

    it "ANDs slots and ORs conditions" do
      sql = apply([[["konto", "in", "18000"]],
        [["amount", "between", 100, 200]],
        [["cost_center", "in", "3150"], ["cost_center", "blank"]]]).to_sql
      expect(sql).to include(%("account_number" IN ('18000')))
      expect(sql).to include(">= 100").and include("<= 200")
      expect(sql).to include(%("cost_center_number" IN ('3150') OR)).and include("IS NULL")
    end

    it "is neutral for invalid operands, unknown keys and wrong arity" do
      sql = apply([[["amount", "between", "abc", 5]], [["booking_date", "gte", "nodate"]],
        [["konto", "in"]], [["nope", "in", "x"]]]).to_sql
      expect(sql).not_to include("WHERE")
    end

    it "filters real rows (closed range AND a second slot)" do
      keep = booking(base_amount: 150, cost_center_number: "3150")
      booking(base_amount: 150, cost_center_number: "9999")
      booking(base_amount: 500, cost_center_number: "3150")
      result = apply([[["cost_center", "in", "3150"]], [["amount", "between", 100, 200]]])
      expect(result.pluck(:id)).to eq([keep.id])
    end

    # The sign variant of the amount (variant_group "Betrag"): signed_base_amount
    # is negative for money leaving the Konto ("C" on a BANK account), so only
    # the |Betrag| variant sees both directions at once.
    it "compares the signed Betrag and, as |Betrag|, its magnitude" do
      incoming = booking(base_amount: 150)
      outgoing = booking(base_amount: 150, debit_credit: "C")
      small = booking(base_amount: 10)
      expect(apply([[["amount", "gte", 100]]]).pluck(:id)).to eq([incoming.id])
      expect(apply([[["amount_abs", "gte", 100]]]).pluck(:id))
        .to match_array([incoming.id, outgoing.id])
      expect(apply([[["amount", "lte", -100]]]).pluck(:id)).to eq([outgoing.id])
      expect(apply([[["amount_abs", "lte", 100]]]).pluck(:id)).to eq([small.id])
      expect(apply([[["amount_abs", "gte", 100]]]).to_sql)
        .to include(%(ABS("datev_bookings"."signed_base_amount") >= 100))
    end

    # The second sign pair (variant_group "Betrag (Original-Währung)") reads the
    # amount as booked: a foreign-currency booking answers with its own figure,
    # while "Betrag" only ever sees the EUR value of the very same row.
    it "compares the Betrag in the booking's own currency, apart from the EUR one" do
      incoming = booking(base_amount: 230, transaction_amount: 1000, transaction_currency: "PLN")
      outgoing = booking(base_amount: 230, transaction_amount: 1000, transaction_currency: "PLN",
        debit_credit: "C")
      euros = booking(base_amount: 500)
      expect(apply([[["amount_original", "gte", 900]]]).pluck(:id)).to eq([incoming.id])
      expect(apply([[["amount", "gte", 900]]]).pluck(:id)).to eq([])
      expect(apply([[["amount", "between", 400, 600]]]).pluck(:id)).to eq([euros.id])
      expect(apply([[["amount_original", "lte", -900]]]).pluck(:id)).to eq([outgoing.id])
      expect(apply([[["amount_original_abs", "gte", 900]]]).pluck(:id))
        .to match_array([incoming.id, outgoing.id])
      expect(apply([[["amount_original", "gte", 900]]]).to_sql)
        .to include(%("signed_transaction_amount" >= 900))
      expect(apply([[["amount_original_abs", "gte", 900]]]).to_sql)
        .to include(%(ABS("datev_bookings"."signed_transaction_amount") >= 900))
    end

    it "matches text case-insensitively, with document fields only in their variants" do
      hit = booking(posting_text: "PFANDrückgabe x")
      doc = booking(posting_text: "anderes", document_field_1: "PFAND-99")
      expect(apply([[["text", "contains", "pfand"]]]).pluck(:id)).to eq([hit.id])
      expect(apply([[["text_document", "contains", "pfand"]]]).pluck(:id)).to eq([doc.id])
      expect(apply([[["text_any", "contains", "pfand"]]]).pluck(:id))
        .to match_array([hit.id, doc.id])
    end

    # Glob: `*` (any run) and `?` (exactly one) are the ONLY wildcards, and the
    # pattern is matched against the WHOLE value -- no implicit %...%, so `*ab*`
    # is the substring form and a bare term matches nothing but itself.
    it "matches a glob against the whole value, * and ? being the only wildcards" do
      prefixed = booking(posting_text: "AB-12 Muster")
      suffixed = booking(posting_text: "Muster AB-12")
      expect(apply([[["text", "glob", "AB*"]]]).pluck(:id)).to eq([prefixed.id])
      expect(apply([[["text", "glob", "*AB*"]]]).pluck(:id))
        .to match_array([prefixed.id, suffixed.id])
      expect(apply([[["text", "glob", "AB-?? Muster"]]]).pluck(:id)).to eq([prefixed.id])
      expect(apply([[["text", "glob", "AB"]]]).pluck(:id)).to eq([])
    end

    it "escapes the LIKE specials of the term, so % and _ stay literal" do
      percent = booking(posting_text: "100% Muster")
      booking(posting_text: "100 Muster")
      expect(apply([[["text", "glob", "100% Muster"]]]).pluck(:id)).to eq([percent.id])
      expect(apply([[["text", "glob", "100_Muster"]]]).pluck(:id)).to eq([])
      expect(apply([[["text", "glob", "a%b_c*d?e"]]]).to_sql)
        .to include(%q(ILIKE 'a\%b\_c%d_e'))
    end

    it "toggles the glob between ILIKE and LIKE, ORing every column of a variant" do
      mixed = booking(posting_text: "Muster AB-12")
      expect(apply([[["text", "glob", "muster*"]]]).pluck(:id)).to eq([mixed.id])
      expect(apply([[["text", "glob_cs", "muster*"]]]).pluck(:id)).to eq([])
      expect(apply([[["text", "glob_cs", "Muster*"]]]).pluck(:id)).to eq([mixed.id])
      case_sensitive_sql = apply([[["text", "glob_cs", "x*"]]]).to_sql
      expect(case_sensitive_sql).to include(" LIKE ")
      expect(case_sensitive_sql).not_to include("ILIKE")
      expect(apply([[["text_any", "glob", "x*"]]]).to_sql.scan("ILIKE").size).to eq(4)
    end

    it "filters by financial year and Stapel through the batch join" do
      def batch(label, financial_year, period_to)
        DatevBookingBatch.create!(
          consultant_number: "1", client_number: "2", label: label,
          period_from: period_to.beginning_of_month, period_to: period_to,
          financial_year_start: Date.new(financial_year, 1, 1),
          import_export: "import"
        )
      end
      b25 = batch("Alt", 2025, Date.new(2025, 12, 31))
      b26 = batch("Neu", 2026, Date.new(2026, 1, 31))
      old_row = booking(datev_booking_batch_id: b25.id)
      new_row = booking(datev_booking_batch_id: b26.id)

      expect(apply([[["financial_year", "in", "2025"]]]).pluck(:id)).to eq([old_row.id])
      expect(apply([[["batch", "in", b26.id.to_s]]]).pluck(:id)).to eq([new_row.id])
      expect(apply([[["batch", "not_in", b26.id.to_s]]]).pluck(:id)).to eq([old_row.id])
    end
  end

  # The strict half of the filter-type protocol against the REAL schema: this is
  # what stops a typo in a host-pinned slot (which the compiler would drop
  # silently) from widening a page's scope.
  describe Wsjrdp::Filtering::FilterSchema do
    it "parses a host-pinned tree and compiles it onto any relation" do
      keep = booking(base_amount: 150, cost_center_number: "3150")
      booking(base_amount: 150, cost_center_number: "9999")
      query = described_class_parse([[["cost_center", "in", "3150"]]])
      scope = Fin::DatevBookingsFilterSchema.compile(query, schema: schema, relation: DatevBooking.all)
      expect(scope.pluck(:id)).to eq([keep.id])
    end

    it "merges the schema's own base relation, so no host repeats the batch join" do
      query = described_class_parse([[["financial_year", "in", "2026"]]])
      sql = Fin::DatevBookingsFilterSchema.compile(query, schema: schema, relation: DatevBooking.all).to_sql
      expect(sql).to include("LEFT OUTER JOIN").and include("datev_booking_batches")
    end

    it "raises for an unknown attribute, naming it and its slot" do
      expect { described_class_parse([[["cost_center", "in", "3150"]], [["typo", "in", "x"]]]) }
        .to raise_error(ArgumentError, /fixed slot 1: unknown attribute "typo"/)
    end

    it "raises for an operator the attribute does not offer" do
      expect { described_class_parse([[["konto", "blank"]]]) }
        .to raise_error(ArgumentError, /does not offer operator "blank"/)
    end

    it "raises for the wrong operand count and for an operand that cannot cast" do
      expect { described_class_parse([[["amount", "between", 100]]]) }
        .to raise_error(ArgumentError, /expects arity two/)
      expect { described_class_parse([[["booking_date", "gte", "nodate"]]]) }
        .to raise_error(ArgumentError, /cannot cast/)
    end

    it "raises for a blank tree" do
      expect { described_class_parse([]) }.to raise_error(ArgumentError, /empty filter tree/)
      expect { described_class_parse([[]]) }.to raise_error(ArgumentError, /slot without conditions/)
    end

    def described_class_parse(tree)
      Fin::DatevBookingsFilterSchema.parse_fixed!(tree, schema: schema)
    end
  end

  describe Wsjrdp::Filtering::Schema do
    it "derives without touching the parent and narrows operators" do
      derived = Fin::DatevBookingsFilterSchema::SCHEMA.derive do |s|
        s.remove(:konto)
        s.operators(:cost_center, %i[in])
      end
      bound = derived.bind(DatevBooking.all)
      expect(bound.find(:konto)).to be_nil
      expect(bound.find(:cost_center).operators.map(&:key)).to eq([:in])
      expect(Fin::DatevBookingsFilterSchema.bound.find(:konto)).to be_present
      expect(Fin::DatevBookingsFilterSchema.bound.find(:cost_center).operators.map(&:key))
        .to eq(%i[in not_in present blank])
    end
  end

  describe "catalog" do
    it "offers the filterable bookings attributes and hides the status" do
      keys = schema.catalog[:attributes].pluck(:key)
      expect(keys).to include(:amount, :konto, :cost_center)
      expect(keys).not_to include(:status, :period)
    end

    # One picker entry "Textsuche" with three sub-variants; the widest one
    # (Buchungstext & Belege) is declared first and is therefore the default.
    it "starts the Textsuche group on Buchungstext & Belege" do
      members = schema.attributes.values.select { |a| a.variant_group == "Textsuche" }
      expect(members.map(&:key)).to eq(%i[text_any text text_document])
      expect(members.map(&:short_key)).to eq(%i[qa q qb])
      expect(members.first.label).to eq("Buchungstext & Belege")
    end

    # Glob sits between the substring operators and `ist genau`; the catalog
    # carries its hint, which the editor shows next to the input.
    it "offers the glob pair on every text variant, with its hint" do
      expect(schema.find(:text_any).operators.map(&:key))
        .to eq(%i[contains contains_cs not_contains not_contains_cs glob glob_cs
          eq eq_cs regex regex_cs])
      glob = schema.catalog[:attributes]
        .find { |a| a[:key] == :text_any }[:operators]
        .find { |o| o[:key] == :glob }
      expect(glob[:label]).to eq("Glob")
      expect(glob[:pickable]).to be true
      expect(glob[:hint]).to include("*").and include("?")
    end

    # One picker entry "Betrag" with a sign toggle, the signed member declared
    # first (= the group's default). Both offer the whole comparison set, the
    # range first, so a fresh condition starts on "im Bereich".
    it "pairs Betrag and |Betrag| in one variant group with its own short key" do
      signed = schema.find(:amount)
      magnitude = schema.find(:amount_abs)
      expect([signed.variant_group, magnitude.variant_group]).to eq(%w[Betrag Betrag])
      expect([signed.label, magnitude.label]).to eq(["Betrag", "|Betrag|"])
      expect([signed.short_key, magnitude.short_key]).to eq(%i[amt amta])
      expect([signed.sign, magnitude.sign]).to eq(%i[signed absolute])
      expect([signed.operand_min, magnitude.operand_min]).to eq([nil, 0])
      expect(signed.operators.map(&:key)).to eq(%i[between lte gte lt gt eq])
      expect(magnitude.pickable_operators.map(&:key)).to eq(%i[between lte gte lt gt eq])
      expect(signed.operators.map(&:label)).to eq(["im Bereich", "≤", "≥", "<", ">", "="])
      expect(schema.attributes.keys.index(:amount))
        .to be < schema.attributes.keys.index(:amount_abs)
    end

    # The sign metadata reaches the builder through the catalog -- that is what
    # turns the group's sub-variant dropdown into the ± / |x| toggle.
    it "ships the sign of both members in the catalog" do
      amounts = schema.catalog[:attributes].select { |a| a[:variant_group] == "Betrag" }
      expect(amounts.pluck(:key)).to eq(%i[amount amount_abs])
      expect(amounts.pluck(:sign)).to eq(%i[signed absolute])
    end

    # The second sign pair, declared right behind "Betrag": same operator list,
    # same ± / |x| toggle, over the amount in the booking's own currency.
    it "pairs Betrag (Original-Währung) and its magnitude in a second sign group" do
      signed = schema.find(:amount_original)
      magnitude = schema.find(:amount_original_abs)
      expect([signed.variant_group, magnitude.variant_group])
        .to eq(["Betrag (Original-Währung)"] * 2)
      expect([signed.label, magnitude.label])
        .to eq(["Betrag (Original-Währung)", "|Betrag (Original-Währung)|"])
      expect([signed.short_key, magnitude.short_key]).to eq(%i[amo amoa])
      expect([signed.sign, magnitude.sign]).to eq(%i[signed absolute])
      expect([signed.operand_min, magnitude.operand_min]).to eq([nil, 0])
      expect(signed.operators.map(&:key)).to eq(%i[between lte gte lt gt eq])
      expect(magnitude.pickable_operators.map(&:key)).to eq(%i[between lte gte lt gt eq])
      keys = schema.attributes.keys
      expect(keys[keys.index(:amount)..keys.index(:amount_original_abs)])
        .to eq(%i[amount amount_abs amount_original amount_original_abs])
    end

    it "ships the sign of the Original-Währung pair in the catalog" do
      amounts = schema.catalog[:attributes]
        .select { |a| a[:variant_group] == "Betrag (Original-Währung)" }
      expect(amounts.pluck(:key)).to eq(%i[amount_original amount_original_abs])
      expect(amounts.pluck(:sign)).to eq(%i[signed absolute])
    end

    # The currency those amounts count in, labelled as the Moss pages label it.
    it "labels the currency attribute Original-Währung" do
      currency = schema.find(:transaction_currency)
      expect([currency.label, currency.short_key]).to eq(["Original-Währung", :cur])
      expect(schema.catalog[:attributes].find { |a| a[:key] == :transaction_currency }[:label])
        .to eq("Original-Währung")
    end

    it "round-trips the Original-Währung pair through its short keys" do
      query = Wsjrdp::Filtering::Query.parse([[["amount_original_abs", "gte", 1000]]])
      expect(Fin::DatevBookingsFilterSchema.encode(query, schema: schema))
        .to eq("!(!(!(amoa,ge,1000)))")
      expect(Fin::DatevBookingsFilterSchema.decode("!(!(!(amo,ge,1000)))", schema: schema).as_json)
        .to eq([[["amount_original", "gte", 1000]]])
    end

    it "round-trips both variants through the short-key wire form" do
      query = Wsjrdp::Filtering::Query.parse([[["amount_abs", "gte", 1000]]])
      wire = Fin::DatevBookingsFilterSchema.encode(query, schema: schema)
      expect(wire).to eq("!(!(!(amta,ge,1000)))")
      expect(Fin::DatevBookingsFilterSchema.decode(wire, schema: schema).as_json)
        .to eq([[["amount_abs", "gte", 1000]]])
      expect(Fin::DatevBookingsFilterSchema.decode("!(!(!(amt,eq,0)))", schema: schema).as_json)
        .to eq([[["amount", "eq", 0]]])
    end

    # The glob pair's short keys, so a hand-written URL and a chip agree.
    it "round-trips a glob condition through its short keys" do
      query = Wsjrdp::Filtering::Query.parse([[["text_any", "glob", "AB*"]]])
      expect(Fin::DatevBookingsFilterSchema.encode(query, schema: schema))
        .to eq("!(!(!(qa,gl,'AB*')))")
      expect(Fin::DatevBookingsFilterSchema.decode("!(!(!(qa,glc,'AB*')))", schema: schema).as_json)
        .to eq([[["text_any", "glob_cs", "AB*"]]])
    end
  end
end
