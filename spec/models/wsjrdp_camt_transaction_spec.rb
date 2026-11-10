# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# What a page lets change by hand on a bank transaction -- its return status
# and its person -- is validated when it changes, and only then. All values are
# invented.
describe WsjrdpCamtTransaction do
  def build_transaction(**attrs)
    described_class.create!(camt_type: "CAMT053", account_identification: "DE-TEST",
      account_servicer_reference: SecureRandom.hex(4), credit_debit_indication: "DBIT",
      signed_base_amount: -12.34, base_currency: "EUR", value_date: Date.new(2026, 4, 2),
      description: "Beispielbuchung", **attrs)
  end

  describe "return status" do
    let(:tx) { build_transaction(return_reason: "MS03") }

    it "takes every status there is, and none" do
      Fin::ReturnEditing.statuses.each_key do |status|
        tx.return_status = status
        expect(tx).to be_valid
      end
      tx.return_status = ""
      expect(tx).to be_valid
    end

    it "refuses any other" do
      tx.return_status = "bogus"

      expect(tx).not_to be_valid
      expect(tx.errors.full_messages).to eq(["Retoure-Status ist kein gültiger Wert"])
    end

    it "does not hold up a row that carries an old value it does not touch" do
      tx.update_column(:additional_info, {"return_debit_status" => "bogus"})
      tx.reload.comment = "anderes Feld"

      expect(tx).to be_valid
    end
  end

  describe "person" do
    let(:tx) { build_transaction }

    it "takes a person that exists, and none" do
      tx.subject = people(:yp_a_1)
      expect(tx).to be_valid
      tx.subject = nil
      expect(tx).to be_valid
    end

    it "refuses an id without a person and a subject that is no person" do
      tx.attributes = {subject_id: 0, subject_type: "Person"}
      expect(tx).not_to be_valid
      expect(tx.errors.full_messages).to eq(["Beteiligte Person wurde nicht gefunden"])

      tx.attributes = {subject_id: groups(:root).id, subject_type: "Group"}
      expect(tx).not_to be_valid
    end
  end
end
