# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp2027::DeregistrationState do
  let(:person) { people(:yp_a_1) }
  let(:unit_bcc) { %w[unit-manager@worldscoutjamboree.de] }

  before do
    groups(:unit_a).update_columns(additional_info: {"unit_code" => "#8B0000", "support_cmt_mail_addresses" => unit_bcc})
    person.update_columns(birthday: Date.new(2010, 6, 1), additional_contact_name_a: "Erika UnitA",
      additional_contact_single: true)
    person.update!(deregistration_effective_date: Date.new(2026, 12, 31), deregistration_issue: "HELP-123",
      deregistration_actual_compensation_cents: 15_000)
  end

  def json = JSON.parse(described_class.new(person.reload).to_json)

  def book_payment(cents)
    AccountingEntry.create!(subject: person, author: people(:admin), amount_cents: cents, amount_currency: "EUR",
      description: "Teilnahmebeitrag", value_date: Date.new(2026, 2, 1), booking_date: Date.new(2026, 2, 1))
  end

  it "answers what the form and its mail need" do
    role_id_name = "YP #{person.id} #{person.short_full_name}"

    aggregate_failures do
      expect(json).to include("person_id" => person.id, "kind" => "withdrawal", "available" => true,
        "not_available_reason" => nil, "issue" => "HELP-123", "status" => person.status,
        "contract_status" => person.contract_status, "role_id_name" => role_id_name,
        "birthday" => "2010-06-01", "deregistration_requested_date" => nil,
        "deregistration_effective_date" => "2026-12-31", "form_mailings" => [], "confirmation_mailings" => [],
        "contract_names" => [person.full_name, "Erika UnitA"], "form_check" => {"errors" => [], "warnings" => []})
      expect(json["form"]).to include("created_date" => nil, "document_id" => nil, "show_contractual_compensation" => true)
      expect(json["form"].keys).to include("reply_due_date", "file_name", "refund_iban", "refund_account_holder")
      expect(json["mail"]).to include("from" => "unit-management@worldscoutjamboree.de", "reply_to" => [],
        "to" => [person.email], "bcc" => unit_bcc + ["unit-management@worldscoutjamboree.de"],
        "unit" => {"group_id" => groups(:unit_a).id, "name" => "Unit A", "source" => "unit"},
        "subject" => "WSJ27 Abmeldung #{role_id_name} HELP-123",
        "confirmation_subject" => "WSJ27 Bestätigung der Abmeldung #{role_id_name} HELP-123")
      expect(json["amounts"].keys).to eq(%w[base_currency regular_full_fee total_fee_reduction total_fee
        amount_paid deregistration_contractual_compensation deregistration_actual_compensation
        deregistration_refund deregistration_open])
    end
  end

  it "answers the amounts in euros, whole ones as integers" do
    person.update!(deregistration_actual_compensation_cents: 40295)
    book_payment(144_000)

    expect(json["amounts"]).to include("base_currency" => "EUR", "deregistration_actual_compensation" => 402.95,
      "deregistration_refund" => 1037.05, "deregistration_open" => 0)
    expect(json["amounts"]["amount_paid"]).to be(1440)
  end

  it "answers the refund account the made form captured, not the one changed since" do
    person.update!(sepa_iban: "DE02120300000000202051", sepa_name: "Kim Muster",
      deregistration_form_show_contractual_compensation: false)
    Wsjrdp2027::DeregistrationForm.new(person.reload).record_creation!
    person.reload.update!(sepa_iban: "DE88100900001234567892", sepa_name: "Anders")

    expect(json["form"]).to include("refund_iban" => "DE02120300000000202051",
      "refund_account_holder" => "Kim Muster", "show_contractual_compensation" => false)
  end

  it "says why there is no form" do
    person.update!(deregistration_kind: "termination")

    expect(json).to include("available" => false, "not_available_reason" => a_string_including("Kündigung"))
  end

  it "wants the refund account where the form names a refund" do
    book_payment(20_000)
    person.update_columns(sepa_iban: nil)

    expect(json["form_check"]["errors"].pluck("code")).to eq(["no_refund_account"])
  end
end
