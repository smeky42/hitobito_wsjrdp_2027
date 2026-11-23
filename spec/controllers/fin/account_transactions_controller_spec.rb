# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# "Alle" (/fin/acc/all): every account's bank and Moss transactions in one
# table. All names and amounts are invented.
describe Fin::AccountTransactionsController do
  render_views

  let(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  let!(:bank) do
    WsjrdpFinAccount.create!(short_name: "Vereinskonto", account_identification: "BANK-ALL",
      opening_balance_cents: 0, opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
  end

  let!(:wallet) do
    WsjrdpFinAccount.create!(short_name: "Moss-Wallet", account_identification: "MOSS-ALL",
      transaction_type: "MossBalanceMovement", opening_balance_cents: 0, opening_balance_currency: "EUR",
      opening_balance_date: Date.new(2026, 1, 1))
  end

  let!(:camt) do
    WsjrdpCamtTransaction.create!(fin_account: bank, camt_type: "CAMT053", account_identification: "BANK-ALL",
      account_servicer_reference: "REF-ALL", credit_debit_indication: "DBIT", signed_base_amount: -40,
      base_currency: "EUR", value_date: Date.new(2026, 5, 2), booking_date: Date.new(2026, 5, 2), description: "Miete Lager", cdtr_name: "Lager GmbH")
  end

  let!(:moss) do
    MossTransaction.create!(type: "MossCardTransaction", moss_transaction_uuid: SecureRandom.uuid,
      fin_account: wallet, signed_total_base_amount: -25, currency: "EUR", booking_date: Date.new(2026, 6, 1),
      transaction_name: "Einkauf", merchant_name: "Muster Markt")
  end

  before { sign_in(person) }

  def doc = Nokogiri::HTML(response.body)

  def cells(key) = doc.css("tr.exp-row td[data-colkey='#{key}']").map { |td| td.text.squish }

  it "lists bank and Moss transactions together, newest first, with their sum" do
    get :index, params: {f: "!(!(!(acc,in,'#{bank.id}','#{wallet.id}')))"}

    expect(response).to be_successful
    expect(cells("booking_date")).to eq(%w[01.06.2026 02.05.2026])
    expect(response.body).to include("2 Transaktionen").and include("-65,00")
    # Account, kind and party are hidden by default; the amount comes last.
    expect(doc.css("tr.exp-row").first.css("td[data-colkey]").pluck("data-colkey").first(3))
      .to eq(%w[booking_date description signed_base_amount])

    get :index, params: {f: "!(!(!(acc,in,'#{bank.id}','#{wallet.id}')))", c: "d,acc,k,dsc,amt"}
    expect(cells("account")).to eq(%w[Moss-Wallet Vereinskonto])
    expect(cells("kind")).to eq(%w[Karte Bank])

    get :index, params: {f: "!(!(!(acc,in,'#{bank.id}','#{wallet.id}')))", c: "d,acc,k,pty,dsc,amt"}
    expect(cells("party")).to eq(["Muster Markt", "Lager GmbH"])
  end

  describe "the description" do
    let(:filter) { "!(!(!(acc,in,'#{bank.id}','#{wallet.id}')))" }

    it "is the one of the row's own table: a return's status, a Moss payment's text" do
      camt.update!(return_reason: "MD06", comment: "Nachfragen")
      get :index, params: {f: filter}

      # Newest first: the Moss payment, then the bank transaction.
      moss_cell, bank_cell = doc.css("tr.exp-row td[data-colkey='description']").to_a
      expect(bank_cell.text).to include("Retoure mit Rückgabe-Grund MD06").and include("Nachfragen")
      expect(moss_cell.at_css(".moss-desc")).to be_present

      get :index, params: {f: filter, c: "d,acc,k,pty,dsc,amt"}
      expect(cells("description").join).not_to include("Gegenseite:")
    end

    it "shows the account and the kind as chips while their columns are hidden, as they are by default" do
      get :index, params: {f: filter, c: "d,acc,k,dsc,amt"}
      # Only the booking day, for a phone, where its column gives way.
      expect(doc.css("td .fin-row-chips > :not(.d-md-none)")).to be_empty

      get :index, params: {f: filter, c: ""} # the default columns
      moss_chips, bank_chips = doc.css("tr.exp-row td[data-colkey='description'] .fin-row-chips").map { |c| c.text.squish }
      # First the booking day (there for a phone), then kind and account.
      expect(moss_chips).to eq("Buchungstag 01.06.2026 Karte Moss-Wallet")
      expect(bank_chips).to eq("Buchungstag 02.05.2026 Bank Vereinskonto")
    end

    it "names the party while its column is hidden, as it is by default" do
      get :index, params: {f: filter}

      expect(cells("description")).to all(include("Gegenseite:"))
      expect(cells("description").join).to include("Lager GmbH").and include("Muster Markt")
    end
  end

  it "opens each row's own detail lazily" do
    get :index, params: {f: "!(!(!(acc,in,'#{bank.id}','#{wallet.id}')))"}

    expect(doc.at_css("turbo-frame#bkframe-at-camt-#{camt.id}")["src"])
      .to start_with(wsjrdp_camt_transaction_path(camt))
    expect(doc.at_css("turbo-frame#bkframe-at-moss-#{moss.id}")["src"])
      .to start_with(moss_transaction_path(moss))
  end

  it "sorts a bank transaction into return, transfer, fee or plain bank, and a Moss top-up into transfer" do
    common = {fin_account: bank, camt_type: "CAMT053", account_identification: "BANK-ALL", base_currency: "EUR",
              credit_debit_indication: "DBIT", signed_base_amount: -1, description: "x"}
    transfer = WsjrdpInternalTransfer.create!(link_meta: {"source" => "manual"})
    WsjrdpCamtTransaction.create!(common.merge(account_servicer_reference: "R1", value_date: Date.new(2026, 7, 1), booking_date: Date.new(2026, 7, 1),
      return_reason: "MS03", bank_transaction_code: "PMNT+IDDT+UPDD"))
    WsjrdpCamtTransaction.create!(common.merge(account_servicer_reference: "R2", value_date: Date.new(2026, 7, 2), booking_date: Date.new(2026, 7, 2),
      internal_transfer_id: transfer.id))
    WsjrdpCamtTransaction.create!(common.merge(account_servicer_reference: "R3", value_date: Date.new(2026, 7, 3), booking_date: Date.new(2026, 7, 3),
      bank_transaction_code: "ACMT+OPCL+ACCC"))
    MossTransaction.create!(type: "MossTopUp", moss_transaction_uuid: SecureRandom.uuid, fin_account: wallet,
      signed_total_base_amount: 1, currency: "EUR", booking_date: Date.new(2026, 7, 4))

    get :index, params: {f: "!(!(!(acc,in,'#{bank.id}','#{wallet.id}')))", c: "d,k,dsc,amt"}

    expect(cells("kind")).to eq(["Umbuchung", "Gebühren/Zinsen", "Umbuchung", "Rückläufer", "Karte", "Bank"])
    expect(doc.css("tr.exp-row").map { |tr| tr["class"][/moss-kind-\S+/] })
      .to eq(%w[moss-kind-top_up moss-kind-bank_fee moss-kind-top_up moss-kind-bank_return
        moss-kind-card_transaction moss-kind-bank])
  end

  it "offers each sortable column's sort in the column menu, a hidden one too" do
    get :index, params: {s: "pty"}

    party = doc.at_css(".exp-cols-col[data-key='party']")
    expect(party.at_css(".exp-cols-check")["checked"]).to be_nil
    expect(party.at_css(".exp-cols-sort a.exp-sort-active")).to be_present
    expect(doc.at_css(".exp-cols-col[data-key='description'] .exp-cols-sort")).to be_nil
  end

  it "offers the sorts of the hidden party, kind and account below the description's header" do
    get :index, params: {c: "d,~acc,~k,dsc,amt"}
    subs = doc.css("th .exp-sub-sorts a.exp-sub-sort")
    expect(subs.map { |a| a.text.delete("⇅").strip }).to eq(%w[Gegenseite Art Konto])

    get :index, params: {c: "d,acc,k,pty,dsc,amt"}
    expect(doc.css("th .exp-sub-sorts")).to be_empty
  end

  it "filters by party, description, person and the free text, and shows person and comment as columns" do
    camt.update!(comment: "Lagerkosten", subject: people(:admin))
    filter = ->(f) { "!(!(!(acc,in,'#{bank.id}','#{wallet.id}')),!(#{f}))" }

    get :index, params: {f: filter.call("!(qp,ct,Lager)"), c: "d,per,cmt,dsc,amt"}
    expect(cells("description").size).to eq(1)
    expect(cells("persons").first).to include(people(:admin).last_name)
    expect(cells("comment")).to eq(["Lagerkosten"])

    get :index, params: {f: filter.call("!(qd,ct,Einkauf)")}
    expect(cells("description").size).to eq(1)
    get :index, params: {f: filter.call("!(q,ct,Lagerkosten)")}
    expect(cells("description").size).to eq(1)
    get :index, params: {f: filter.call("!(per,ct,#{people(:admin).last_name})")}
    expect(cells("description").size).to eq(1)
  end

  it "never shows the value date as a column, but a bank row's in the description where it differs" do
    camt.update!(booking_date: Date.new(2026, 5, 4))
    get :index, params: {f: "!(!(!(acc,in,'#{bank.id}')))", c: "d,vd,dsc,amt"}

    expect(doc.css("td[data-colkey='value_date']")).to be_empty
    expect(doc.css(".exp-cols-col[data-key='value_date']")).to be_empty
    expect(cells("description").join).to include("Valuta 02.05.2026")
  end

  it "narrows the rows to the chosen kinds" do
    get :index, params: {u: "kind.bank", f: "!(!(!(acc,in,'#{bank.id}','#{wallet.id}')))", c: "d,k,dsc,amt"}

    expect(cells("kind")).to eq(%w[Bank])
  end

  it "shows 'Alle' as the first account tab, active" do
    get :index

    tabs = doc.css(".fin-account-tabs li")
    expect(tabs.first.text.strip).to eq("Alle")
    expect(tabs.first["class"]).to eq("active")
  end

  it "applies the builder's filter back to the page" do
    post :apply, params: {filter_json: [[["text", "contains", "Lager"]]].to_json}

    expect(response).to have_http_status(:see_other)
    expect(response.location).to include("/fin/acc/all?f=")
  end
end
