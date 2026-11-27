# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Fin::DebitEditing do
  def debit(status) = WsjrdpDirectDebitPreNotification.new(payment_status: status)

  def params(attrs) = ActionController::Parameters.new(attrs)

  it "lets a debit only announced change its payment data, a debit in a SEPA file its comment alone" do
    expect(described_class.fields(debit("pre_notified")).keys).to contain_exactly(:amount_eur, :description,
      :endtoend_id, :try_skip, :comment, :mandate_id, :mandate_date, :dbtr_name, :dbtr_iban, :dbtr_bic, :dbtr_address)
    expect(described_class.fields(debit("xml_generated")).keys).to eq(%i[comment])
  end

  it "adds the status for the manage tier, whatever the debit's status" do
    expect(described_class.fields(debit("pre_notified"), manage: true).keys).to include(:payment_status, :mandate_id)
    expect(described_class.fields(debit("xml_generated"), manage: true).keys).to eq(%i[comment payment_status])
  end

  it "reads the amount as the money input sends it and drops a status the list does not know" do
    permitted = described_class.permitted(debit("pre_notified"),
      params(amount_eur: "1.234,50", payment_status: "paid", description: "x"), manage: true)

    expect(permitted.to_h).to eq("amount_eur" => "1234.50", "description" => "x")
  end

  it "drops what the debit's status and the tier do not let change" do
    permitted = described_class.permitted(debit("xml_generated"),
      params(comment: "ok", amount_eur: "1,00", payment_status: "skipped"))

    expect(permitted.to_h).to eq("comment" => "ok")
  end
end
