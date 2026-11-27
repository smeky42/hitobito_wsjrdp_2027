# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe "Wsjrdp::Sync master data" do
  include SyncSpecHelpers

  let(:admin) { people(:cmt_leader) }
  let(:suppliers_key) { Wsjrdp::Sync::MossApi::Suppliers.key }
  let(:ledger_key) { Wsjrdp::Sync::MossApi::LedgerAccounts.key }

  before do
    WsjrdpLedgerAccount.create!(number: "01000", name: "Konzessionen, Rechte", moss_status: "deactivated")
    WsjrdpLedgerAccount.create!(number: "41030", name: "Teilnehmerbeiträge", moss_status: "active")
    WsjrdpCostCenter.create!(number: "3300", name: "Foodhouse", moss_status: "active")
    WsjrdpCostCenter.create!(number: "9990", name: "Unbekannt", moss_status: "deactivated")
    WsjrdpSphere.delete_all
    WsjrdpSphere.create!(number: "3", name: "Zweckbetrieb", moss_status: "active")
    WsjrdpPersonalAccount.create!(number: "700043", name: "Verein Stuttgart", moss_status: "active",
      moss_account_holder_name: "VUJ e.V.", moss_type: "COMPANY", datev_nummer_fremdsystem: "5a000000-0000-4")
    WsjrdpPersonalAccount.create!(number: "700050", name: "Konflikt GmbH", moss_status: "active",
      moss_uuid: "5a000000-0000-4000-8000-0000000000ee")
    WsjrdpPersonalAccount.create!(number: "700009", name: "Unbekannter Kreditor", moss_status: "deactivated")
  end

  def start(keys = [suppliers_key])
    Wsjrdp::Sync::Start.new(source: :moss_api, selection: keys, client: client, actor: admin,
      now: Time.zone.parse("2026-11-27 10:00:00 UTC")).call
  end

  def apply(run)
    Wsjrdp::Sync::Apply.new(run.reload, actor: admin, confirmed: true, warnings_confirmed: true).call
  end

  def plan(run, key) = run.parts.reload.find { |part| part.part_key == key }.plan_object

  def notice(run, key, code) = plan(run, key).warnings.find { |warning| warning.code == code }

  it "takes the parts a supplier refers to along, the organisation included" do
    expect(Wsjrdp::Sync.expand([suppliers_key])).to eq(Wsjrdp::Sync.parts.map(&:key) -
      [Wsjrdp::Sync::MossApi::Users.key, Wsjrdp::Sync::MossApi::Dimensions.key,
        Wsjrdp::Sync::MossApi::BankAccounts.key])
  end

  it "pads a Moss account code to the Sachkontenlänge" do
    expect(%w[1000 41030 123456 12a].map { |code| WsjrdpLedgerAccount.number_from(code) })
      .to eq(["01000", "41030", nil, nil])
  end

  it "matches by UUID, else by number, creates the rest and clears the status of rows Moss no longer has" do
    run = start
    expect(run.warnings?).to be(true)

    apply(run)

    expect(run.reload.status).to eq("applied")
    expect(WsjrdpLedgerAccount.find_by!(number: "01000").moss_uuid).to eq("ea000000-0000-4000-8000-000000001000")
    expect(WsjrdpLedgerAccount.find_by!(number: "41030").name).to eq("Teilnehmendenbeiträge")
    expect(WsjrdpLedgerAccount.find_by!(number: "66600")).to have_attributes(moss_status: "active", account_kind: "UNKNOWN")
    expect(WsjrdpCostCenter.find_by!(number: "9990").moss_status).to be_nil
    expect(WsjrdpCostCenter.find_by!(number: "3800").moss_uuid).to eq("e1000000-0000-4000-8000-000000000002")
    expect(WsjrdpPersonalAccount.find_by!(number: "700009").moss_status).to be_nil
  end

  it "fills a supplier with what its Moss references name, and leaves what only the CSV or DATEV bring" do
    apply(start)

    created = WsjrdpPersonalAccount.find_by!(number: "700131")
    expect(created).to have_attributes(name: "Hostel Gdańsk", account_kind: "CREDITOR", moss_default_currency: "PLN",
      moss_default_ledger_account_number: "66600", moss_default_cost_center_number: "3300",
      moss_default_sphere_number: "3", moss_default_team_name: "Team Eins",
      default_moss_payment_term_uuid: "f1000000-0000-4000-8000-000000000001",
      default_moss_vat_rate_uuid: "f2000000-0000-4000-8000-000000000019", moss_type: nil)
    matched = WsjrdpPersonalAccount.find_by!(number: "700043")
    expect(matched).to have_attributes(moss_uuid: "5a000000-0000-4000-8000-000000700043", iban: "DE02120300000000202051",
      city: "Stuttgart", moss_account_holder_name: "VUJ e.V.", moss_type: "COMPANY",
      datev_nummer_fremdsystem: "5a000000-0000-4")
    expect(MossPaymentTerm.sole).to have_attributes(net_due_days: 14, lines: [include("discountPercentage" => 2.0)])
    expect(MossTaxRate.sole).to have_attributes(rate: 19, reverse_charge: false, tax_type: "VAT")
  end

  it "keeps a record out whose UUID and number point at different rows, with both in the warning" do
    run = start
    conflict = notice(run, suppliers_key, "number_conflict")

    expect(conflict.level).to eq("warning")
    expect(conflict.items.values.sole).to include("Moss Nr. 700050", "5a000000-0000-4000-8000-000000700050",
      "Hitobito Nr. 700050, UUID 5a000000-0000-4000-8000-0000000000ee")

    apply(run)

    expect(WsjrdpPersonalAccount.find_by!(number: "700050").moss_uuid).to eq("5a000000-0000-4000-8000-0000000000ee")
  end

  it "leaves the rows of a conflict as they are, status included" do
    key = Wsjrdp::Sync::MossApi::CostCenters.key
    WsjrdpCostCenter.find_by!(number: "3300").update!(moss_uuid: "e1000000-0000-4000-8000-000000000002")
    WsjrdpCostCenter.create!(number: "3800", name: "UL-Team-Treffen", moss_status: "active")
    run = start([key])

    kinds = notice(run, key, "number_conflict").items.values.map { |text| text.split(":").first }
    expect(kinds).to contain_exactly("Nummer hat in Hitobito eine andere UUID", "UUID gehört in Hitobito zu einer anderen Nummer")
    expect(plan(run, key).changes.map(&:action)).to eq(["remove"]) # 9990 only

    apply(run)

    expect(WsjrdpCostCenter.find_by!(number: "3300")).to have_attributes(moss_status: "active",
      moss_uuid: "e1000000-0000-4000-8000-000000000002")
    expect(WsjrdpCostCenter.find_by!(number: "3800")).to have_attributes(moss_status: "active", moss_uuid: nil)
  end

  it "keeps both records out when Moss has a number twice" do
    lists["suppliers"] << lists["suppliers"].second.merge("id" => "5a000000-0000-4000-8000-0000000001ff")
    run = start

    expect(notice(run, suppliers_key, "number_conflict").items.keys)
      .to include("5a000000-0000-4000-8000-000000700131", "5a000000-0000-4000-8000-0000000001ff")
    expect(plan(run, suppliers_key).changes.map(&:key)).not_to include("5a000000-0000-4000-8000-000000700131")
  end

  it "warns before clearing the status of every row" do
    key = Wsjrdp::Sync::MossApi::Spheres.key
    lists["dimensions/#{MossDimension::COST_CARRIER_UUID}/items"] = []

    notice = notice(start([key]), key, "many_cleared")

    expect(notice).to have_attributes(level: "warning", items: {"number:3" => "3 Zweckbetrieb"})
  end

  it "keeps a record out whose code is no number of the table, and points at unknown references" do
    run = start

    expect(notice(run, suppliers_key, "invalid_number").items.values).to eq(["AB12 Ohne Nummer"])
    expect(notice(run, suppliers_key, "unknown_reference").items.values.sole)
      .to eq("AB12 Ohne Nummer → Sachkonto ea000000-0000-4000-8000-0000000000ff")
  end

  it "leaves the row of a record whose code no longer fits" do
    WsjrdpPersonalAccount.find_by!(number: "700043").update!(moss_uuid: "5a000000-0000-4000-8000-000000700043")
    lists["suppliers"].first["code"] = "7000430"
    run = start

    expect(plan(run, suppliers_key).changes.map(&:key)).not_to include("5a000000-0000-4000-8000-000000700043")
    expect(notice(run, suppliers_key, "invalid_number").items).to include("5a000000-0000-4000-8000-000000700043")
  end

  it "finds the rows of change keys, a number with letters included" do
    row = WsjrdpCostCenter.create!(number: "K12", name: "Mit Buchstaben")

    expect(Wsjrdp::Sync::MossApi::CostCenters.records_for(["number:k12"])).to eq("number:k12" => row)
  end

  it "names a reference to a record without a number of its own" do
    lists["expense-accounts"].last["code"] = "66A00"
    run = start

    expect(notice(run, suppliers_key, "unknown_reference").items.values)
      .to include("700131 Hostel Gdańsk → Sachkonto ea000000-0000-4000-8000-000000066600")
  end

  it "trims names and says when Moss renames a row" do
    run = start([ledger_key])

    expect(notice(run, ledger_key, "name_changed").items.values).to eq(["Teilnehmerbeiträge → Teilnehmendenbeiträge"])
  end

  it "keeps the dimensions with the table of their items" do
    apply(start([Wsjrdp::Sync::MossApi::Dimensions.key]))

    expect(MossDimension.order(:moss_dimension_uuid).pluck(:items_table, :status))
      .to eq([["wsjrdp_cost_centers", "ACTIVE"], ["wsjrdp_spheres", "ACTIVE"], [nil, "DELETED"]])
  end

  it "gives a row back its status when Moss returns it again" do
    WsjrdpSphere.find_by!(number: "3").update!(moss_status: nil, moss_uuid: "e2000000-0000-4000-8000-000000000003")
    key = Wsjrdp::Sync::MossApi::Spheres.key

    apply(start([key]))

    expect(WsjrdpSphere.find_by!(number: "3").moss_status).to eq("active")
  end

  it "clears no status while a list is short" do
    allow(client).to receive(:total_items).and_call_original
    allow(client).to receive(:total_items).with(Wsjrdp::Sync::MossApi::CostCenters.path).and_return(5)
    key = Wsjrdp::Sync::MossApi::CostCenters.key
    run = start([key])

    expect(plan(run, key).changes.map(&:action)).not_to include("remove")
    expect(notice(run, key, "incomplete")).to be_present
  end

  it "changes nothing when run again" do
    apply(start)

    expect(start.status).to eq("unchanged")
  end
end
