# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The generic CNF filter engine (doc/generic_filter_builder.md): Rison codec,
# URL codec (short keys), compiler (Arel, 3VL, neutral-on-invalid), schema
# derive/bind. Uses the bookings schema as the concrete example dataset.
describe Filtering do
  let(:schema) { DatevBookingsFilter.bound }

  def booking(attrs)
    defaults = {status: DatevBooking::STATUS_ACTIVE, currency: "EUR",
                original_amount: 10, debit_credit: "D",
                account_number: "18000", offsetting_account_number: "66500",
                account_type: "BANK", offsetting_account_type: "EXPENSE"}
    DatevBooking.create!(defaults.merge(attrs))
  end

  describe Filtering::UrlCodec do
    let(:tree) { [[["amount", "between", 100, 200]], [["cost_center", "in", "3150"], ["cost_center", "blank"]]] }
    let(:query) { Filtering::Query.parse(tree) }

    it "encodes with short keys and round-trips" do
      rison = described_class.encode(query, schema: schema)
      expect(rison).to eq("!(!(!(amt,bt,100,200)),!(!(cc,in,'3150'),!(cc,bl)))")
      expect(described_class.decode(rison, schema: schema).as_json).to eq(query.as_json)
    end

    it "accepts full keys and canonicalizes to them" do
      decoded = described_class.decode("!(!(!(amount,between,1,2)))", schema: schema)
      expect(decoded.as_json).to eq([[["amount", "between", 1, 2]]])
    end

    it "drops unknown attributes/operators and survives garbage" do
      decoded = described_class.decode("!(!(!(nope,in,x),!(amt,ge,5)))", schema: schema)
      expect(decoded.as_json).to eq([[["amount", "gte", 5]]])
      expect(described_class.decode("!!!garbage", schema: schema)).to be_empty
      expect(described_class.decode(nil, schema: schema)).to be_empty
    end

    it "escapes only URL-breaking characters" do
      expect(described_class.escape_for_query("!(a b&c+d%e#f)"))
        .to eq("!(a%20b%26c%2Bd%25e%23f)")
    end
  end

  describe Filtering::Compiler do
    def apply(tree, hidden: DatevBookingsFilter::HIDDEN)
      described_class.new(schema).apply(Filtering::Query.parse(tree), hidden: hidden)
    end

    it "ANDs slots, ORs conditions, prefixes hidden conditions" do
      sql = apply([[["amount", "between", 100, 200]],
        [["cost_center", "in", "3150"], ["cost_center", "blank"]]]).to_sql
      expect(sql).to include(%("status" IN ('active')))
      expect(sql).to include(">= 100").and include("<= 200")
      expect(sql).to include(%("cost_center_number" IN ('3150') OR)).and include("IS NULL")
    end

    it "is neutral for invalid operands, unknown keys and wrong arity" do
      sql = apply([[["amount", "between", "abc", 5]], [["booking_date", "gte", "nodate"]],
        [["konto", "in"]], [["nope", "in", "x"]]], hidden: []).to_sql
      expect(sql).not_to include("WHERE")
    end

    it "filters real rows (closed range, hidden status)" do
      keep = booking(original_amount: 150, cost_center_number: "3150")
      booking(original_amount: 150, cost_center_number: "9999")
      booking(original_amount: 500, cost_center_number: "3150")
      soft = booking(original_amount: 150, cost_center_number: "3150")
      soft.update!(status: "soft_deleted")
      result = apply([[["amount", "between", 100, 200]], [["cost_center", "in", "3150"]]])
      expect(result.pluck(:id)).to eq([keep.id])
    end

    it "matches text case-insensitively, with document fields only in their variants" do
      hit = booking(description: "PFANDrückgabe x")
      doc = booking(description: "anderes", document_field_1: "PFAND-99")
      expect(apply([[["text", "contains", "pfand"]]]).pluck(:id)).to eq([hit.id])
      expect(apply([[["text_document", "contains", "pfand"]]]).pluck(:id)).to eq([doc.id])
      expect(apply([[["text_any", "contains", "pfand"]]]).pluck(:id))
        .to match_array([hit.id, doc.id])
    end
  end

  describe Filtering::Schema do
    it "derives without touching the parent and narrows operators" do
      derived = DatevBookingsFilter::SCHEMA.derive do |s|
        s.remove(:konto)
        s.operators(:cost_center, %i[in])
      end
      bound = derived.bind(DatevBooking.all)
      expect(bound.find(:konto)).to be_nil
      expect(bound.find(:cost_center).operators.map(&:key)).to eq([:in])
      expect(DatevBookingsFilter.bound.find(:konto)).to be_present
      expect(DatevBookingsFilter.bound.find(:cost_center).operators.map(&:key))
        .to eq(%i[in not_in present blank])
    end

    it "rejects duplicate short_keys and unknown operator keys" do
      expect {
        Filtering::Schema.define do |s|
          s.attribute key: :a, short_key: :x, label: "A", type: Filtering::Types::TEXT,
            operators: %i[contains], column: :description
          s.attribute key: :b, short_key: :x, label: "B", type: Filtering::Types::TEXT,
            operators: %i[contains], column: :description
        end
      }.to raise_error(ArgumentError, /short_key/)
      expect {
        Filtering::Schema.define do |s|
          s.attribute key: :a, label: "A", type: Filtering::Types::TEXT,
            operators: %i[nope], column: :description
        end
      }.to raise_error(KeyError)
    end
  end

  describe "catalog" do
    it "projects only catalog attributes, without SQL or short_keys" do
      catalog = schema.catalog
      keys = catalog[:attributes].map { |a| a[:key] }
      expect(keys).to include(:amount, :konto, :cost_center)
      expect(keys).not_to include(:status)
      expect(catalog.to_json).not_to include("short_key")
      expect(catalog.to_json).not_to include("column")
    end
  end
end
