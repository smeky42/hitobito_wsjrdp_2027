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
  before_all(setup_fixtures: true) {}

  let_it_be(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  let_it_be(:bank) do
    WsjrdpFinAccount.create!(short_name: "Vereinskonto", account_identification: "BANK-ALL",
      opening_balance_cents: 0, opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
  end

  let_it_be(:wallet) do
    WsjrdpFinAccount.create!(short_name: "Moss-Wallet", account_identification: "MOSS-ALL",
      transaction_type: "MossBalanceMovement", opening_balance_cents: 0, opening_balance_currency: "EUR",
      opening_balance_date: Date.new(2026, 1, 1))
  end

  let_it_be(:camt, refind: true) do
    WsjrdpCamtTransaction.create!(fin_account: bank, camt_type: "CAMT053", account_identification: "BANK-ALL",
      account_servicer_reference: "REF-ALL", credit_debit_indication: "DBIT", signed_base_amount: -40,
      base_currency: "EUR", value_date: Date.new(2026, 5, 2), booking_date: Date.new(2026, 5, 2),
      description: "Miete Lager", cdtr_name: "Lager GmbH")
  end

  let_it_be(:moss) do
    MossTransaction.create!(type: "MossCardTransaction", moss_transaction_uuid: SecureRandom.uuid,
      fin_account: wallet, signed_total_base_amount: -25, currency: "EUR", booking_date: Date.new(2026, 6, 1),
      transaction_name: "Einkauf", merchant_name: "Muster Markt")
  end

  let(:both_accounts) { "!(!(!(acc,in,'#{bank.id}','#{wallet.id}')))" }

  before { sign_in(person) }

  def rows = controller.transactions.page.to_a

  def state = controller.table_state

  it "lists bank and Moss transactions together, newest first, with account, kind, party and sum" do
    get :index, params: {f: both_accounts}

    expect(rows.map { |row| [row.booking_date, row.account_name, row.kind, row.party] }).to eq([
      [Date.new(2026, 6, 1), "Moss-Wallet", "MossCardTransaction", "Muster Markt"],
      [Date.new(2026, 5, 2), "Vereinskonto", "bank", "Lager GmbH"]
    ])
    expect([controller.transactions.total_count, controller.transactions.total_sum]).to eq([2, -65])
    expect(state.visible_column_keys.first(3)).to eq(%w[booking_date description signed_base_amount])
    expect(state.visible_column_keys).not_to include("account", "kind", "party")
  end

  it "sorts a bank transaction into return, transfer, fee or plain bank, and a Moss top-up into transfer" do
    common = {fin_account: bank, camt_type: "CAMT053", account_identification: "BANK-ALL", base_currency: "EUR",
              credit_debit_indication: "DBIT", signed_base_amount: -1, description: "x"}
    transfer = WsjrdpInternalTransfer.create!(link_meta: {"source" => "manual"})
    WsjrdpCamtTransaction.create!(common.merge(account_servicer_reference: "R1", value_date: Date.new(2026, 7, 1),
      booking_date: Date.new(2026, 7, 1), return_reason: "MS03", bank_transaction_code: "PMNT+IDDT+UPDD"))
    WsjrdpCamtTransaction.create!(common.merge(account_servicer_reference: "R2", value_date: Date.new(2026, 7, 2),
      booking_date: Date.new(2026, 7, 2), internal_transfer_id: transfer.id))
    WsjrdpCamtTransaction.create!(common.merge(account_servicer_reference: "R3", value_date: Date.new(2026, 7, 3),
      booking_date: Date.new(2026, 7, 3), bank_transaction_code: "ACMT+OPCL+ACCC"))
    MossTransaction.create!(type: "MossTopUp", moss_transaction_uuid: SecureRandom.uuid, fin_account: wallet,
      signed_total_base_amount: 1, currency: "EUR", booking_date: Date.new(2026, 7, 4))

    get :index, params: {f: both_accounts}

    expect(rows.map(&:kind)).to eq(%w[transfer bank_fee transfer bank_return MossCardTransaction bank])
  end

  it "narrows the rows to the chosen kinds" do
    get :index, params: {u: "kind.bank", f: both_accounts}

    expect(rows.map(&:kind)).to eq(%w[bank])
  end

  it "never shows the value date as a column" do
    get :index, params: {f: both_accounts, c: "d,vd,dsc,amt"}

    expect(state.visible_column_keys).not_to include("value_date")
  end

  describe "filters" do
    def index(condition) = get(:index, params: {f: "!(!(!(acc,in,'#{bank.id}','#{wallet.id}')),!(#{condition}))"})

    it "by the party, with person and comment on the row" do
      camt.update!(comment: "Lagerkosten", subject: people(:admin))

      index("!(qp,ct,Lager)")

      expect(rows.map(&:id)).to eq([camt.id])
      expect(rows.first.persons).to include(people(:admin).last_name)
      expect(rows.first.comment).to eq("Lagerkosten")
    end

    it "by the description" do
      index("!(qd,ct,Einkauf)")

      expect(rows.map(&:id)).to eq([moss.id])
    end

    it "by the free text, the comment included" do
      camt.update_columns(comment: "Lagerkosten")

      index("!(q,ct,Lagerkosten)")

      expect(rows.map(&:id)).to eq([camt.id])
    end

    it "by the person" do
      camt.update!(subject: people(:admin))

      index("!(per,ct,#{people(:admin).last_name})")

      expect(rows.map(&:id)).to eq([camt.id])
    end
  end

  # The description is the one of the row's own table, and it stands in for the
  # columns that are hidden.
  describe "the rendered description" do
    render_views

    def doc = Nokogiri::HTML(response.body)

    def descriptions = doc.css("tr.exp-row td[data-colkey='description']").map { |td| td.text.squish }

    it "carries status, value date, party, kind and account while their columns are hidden, and opens lazily" do
      camt.update_columns(return_reason: "MD06", comment: "Nachfragen", booking_date: Date.new(2026, 5, 4))

      get :index, params: {f: both_accounts}

      moss_text, bank_text = descriptions
      expect(bank_text).to include("MD06", "Nachfragen", "02.05.2026", "Lager GmbH", "Vereinskonto")
      expect(moss_text).to include("Muster Markt", "Moss-Wallet")
      expect(doc.at_css("tr.exp-row td[data-colkey='description'] .moss-desc")).to be_present
      expect(doc.at_css("turbo-frame#bkframe-at-camt-#{camt.id}")["src"]).to start_with(wsjrdp_camt_transaction_path(camt))
      expect(doc.at_css("turbo-frame#bkframe-at-moss-#{moss.id}")["src"]).to start_with(moss_transaction_path(moss))
    end

    # Only the booking day stays, for a phone, where its column gives way.
    it "leaves party, kind and account to their columns once they are shown" do
      get :index, params: {f: both_accounts, c: "d,acc,k,pty,dsc,amt"}

      expect(doc.css("td .fin-row-chips > :not(.d-md-none)")).to be_empty
      expect(descriptions.join).not_to include("Lager GmbH", "Vereinskonto", "Moss-Wallet")
    end
  end

  it "applies the builder's filter back to the page" do
    post :apply, params: {filter_json: [[["text", "contains", "Lager"]]].to_json}

    expect(response).to have_http_status(:see_other)
    expect(response.location).to include("/fin/acc/all?f=")
  end
end
