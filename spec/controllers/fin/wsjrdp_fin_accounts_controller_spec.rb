# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The statement of ONE finance account (/fin/acc/:id), for the Moss wallet
# (its Moss transactions) and for a bank account (its camt transactions), and
# the account list. All names, numbers and amounts are invented.
describe Fin::WsjrdpFinAccountsController do
  before_all(setup_fixtures: true) {}

  let_it_be(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let_it_be(:manager) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }
  let_it_be(:auditor) do
    Fabricate(Group::Extern::FinanceAuditor.name.to_sym,
      group: Group::Extern.create!(name: "Extern", parent: groups(:root))).person
  end

  def new_account(name, identification, **attrs)
    WsjrdpFinAccount.create!(short_name: name, account_identification: identification, opening_balance_cents: 0,
      opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1), **attrs)
  end

  let_it_be(:wallet, reload: true) do
    new_account("Moss-Wallet", "MOSS-WALLET-TEST", transaction_type: "MossBalanceMovement",
      opening_balance_cents: 100_000)
  end
  let_it_be(:bank, reload: true) do
    new_account("Vereinskonto", "DE19100100103333333333", iban: "DE19100100103333333333",
      opening_balance_cents: 10_000)
  end

  # One transaction per kind on the wallet, by Buchungsdatum, and one on
  # another wallet; two camt transactions on the bank account, the later one
  # incoming.
  let_it_be(:wallet_kinds) do
    other = new_account("Anderes Wallet", "MOSS-OTHER-TEST", transaction_type: "MossBalanceMovement")
    MossTransaction.create!(type: "MossTopUp", moss_transaction_uuid: SecureRandom.uuid, fin_account: other,
      signed_total_base_amount: 7, currency: "EUR", booking_date: Date.new(2026, 8, 1))
    {"MossCardTransaction" => [-25, Date.new(2026, 5, 3)], "MossReimbursement" => [-60, Date.new(2026, 6, 1)],
     "MossInvoice" => [-100, Date.new(2026, 7, 15)], "MossTopUp" => [500, Date.new(2027, 1, 20)]}
      .each do |type, (amount, date)|
      MossTransaction.create!(type: type, moss_transaction_uuid: SecureRandom.uuid, fin_account: wallet,
        signed_total_base_amount: amount, currency: "EUR", booking_date: date)
    end
    %w[MossTopUp MossInvoice MossReimbursement MossCardTransaction]
  end

  let_it_be(:camts) do
    [[-12.34, Date.new(2026, 4, 2), {}],
      [-3, Date.new(2026, 3, 2), {return_reason: "MS03", bank_transaction_code: "PMNT+IDDT+UPDD"}],
      [50, Date.new(2026, 5, 1), {}]].map do |amount, date, attrs|
      WsjrdpCamtTransaction.create!(fin_account: bank, camt_type: "CAMT053",
        account_identification: bank.account_identification, account_servicer_reference: SecureRandom.hex(4),
        credit_debit_indication: amount.negative? ? "DBIT" : "CRDT", signed_base_amount: amount,
        base_currency: "EUR", value_date: date, booking_date: date, description: "Buchung", **attrs)
    end
  end

  # The manage tier holds once the session picks it, not by default.
  def sign_in_manage_tier
    sign_in(manager)
    session[:max_finance_permission] = "finance_manage"
  end

  def camt_rows = controller.camt_transactions.page

  describe "GET show" do
    before { sign_in(person) }

    it "shows the wallet's own Moss transactions, newest first" do
      get :show, params: {id: wallet.id}

      expect(controller.send(:transactions).page.map(&:type)).to eq(wallet_kinds)
    end

    it "shows a bank account's camt transactions, newest first, with their sum" do
      get :show, params: {id: bank.id}

      expect(camt_rows.map(&:booking_date)).to eq([Date.new(2026, 5, 1), Date.new(2026, 4, 2), Date.new(2026, 3, 2)])
      expect(controller.camt_transactions.total_sum).to eq(BigDecimal("34.66"))
    end

    it "filters a bank account's transactions by the URL" do
      get :show, params: {id: bank.id, ctf: "!(!(!(amt,ge,0)))"}

      expect(camt_rows.map(&:signed_base_amount)).to eq([50])
    end

    it "narrows a bank account's transactions to the kind chosen" do
      get :show, params: {id: bank.id, ctu: "kind.bank_return"}

      expect(camt_rows.map(&:id)).to eq([camts.second.id])
    end

    it "answers a list row's frame with the detail alone" do
      request.headers["Turbo-Frame"] = "bkframe-acc-#{wallet.id}"
      get :show, params: {id: wallet.id}

      expect(response).to render_template(:detail_frame)
      expect(controller.detail_format_context).to be_embedded
    end

    context "with views" do
      render_views

      it "shows a wallet's Moss fields once the sync has linked it" do
        request.headers["Turbo-Frame"] = "bkframe-acc-#{wallet.id}"
        wallet.update!(moss_bank_account_uuid: "b0000000-0000-4000-8000-000000000001", moss_balance: 12.5,
          moss_currency: "EUR")
        get :show, params: {id: wallet.id}

        expect(Nokogiri::HTML(response.body).css("dd").map(&:text).join).to include("b0000000-0000-4000-8000-000000000001")
      end
    end

    it "shows the page's own frame as the page's detail" do
      request.headers["Turbo-Frame"] = "bkframe-accpage-#{wallet.id}"
      get :show, params: {id: wallet.id}

      expect(controller.detail_format_context).to be_regular
    end
  end

  describe "GET index" do
    it "lists every account with the balance of its statement, sortable by it" do
      sign_in(person)
      get :index, params: {as: "sa~"}

      # The wallet's balance counts its Moss bookings, of which there are none.
      balances = controller.accounts.page.to_h { |account| [account.id, account.balance_eur] }
      expect(balances.values_at(wallet.id, bank.id)).to eq([BigDecimal(1000), BigDecimal("134.66")])
      expect(balances.keys.index(wallet.id)).to be < balances.keys.index(bank.id)
    end
  end

  describe "POST apply" do
    before { sign_in(person) }

    it "encodes the wallet's filter and redirects (PRG) back to the account" do
      post :apply, params: {id: wallet.id, filter_json: [[["kind", "in", "MossTopUp"]]].to_json}

      expect(response).to have_http_status(:see_other)
      expect(CGI.unescape(response.location)).to end_with("/fin/acc/#{wallet.id}?f=!(!(!(k,in,'MossTopUp')))")
    end

    it "encodes a bank account's filter into its own param" do
      post :apply, params: {id: bank.id, filter_json: [[["amount", "gte", "0"]]].to_json}

      expect(CGI.unescape(response.location)).to include("/fin/acc/#{bank.id}?ctf=!(!(!(amt,ge,")
    end
  end

  describe "PATCH update" do
    let(:changes) { {short_name: "Neuer Name"} }

    before { sign_in(person) }

    it "saves and returns to the reading page with the detail open" do
      patch :update, params: {id: wallet.id, wsjrdp_fin_account: changes}

      expect(response).to redirect_to(wsjrdp_fin_account_path(wallet, details: "open"))
      expect(wallet.reload.short_name).to eq("Neuer Name")
    end

    it "lets the write tier change the names only" do
      patch :update, params: {id: wallet.id, wsjrdp_fin_account: {short_name: "Neu", position: 7}}

      expect(wallet.reload).to have_attributes(short_name: "Neu", position: wallet.position)
    end

    it "shows the edit page again when the record is invalid" do
      allow_any_instance_of(WsjrdpFinAccount).to receive(:save).and_return(false)
      patch :update, params: {id: wallet.id, wsjrdp_fin_account: changes}

      expect(response).to have_http_status(:bad_request)
      expect(response).to render_template(:edit)
    end

    context "from a frame" do
      before { request.accept = "text/vnd.turbo-stream.html, text/html" }

      def redirect_url = Nokogiri::HTML(response.body).at_css("turbo-stream[action='redirect_top']")["url"]

      it "leaves the page's frame for the page with the detail open" do
        request.headers["Turbo-Frame"] = "bkframe-accpage-#{wallet.id}"
        patch :update, params: {id: wallet.id, wsjrdp_fin_account: changes}

        expect(redirect_url).to eq(wsjrdp_fin_account_path(wallet, details: "open"))
      end

      it "leaves a list row's frame for the list with the row open" do
        request.headers["Turbo-Frame"] = "bkframe-acc-#{wallet.id}"
        patch :update, params: {id: wallet.id, wsjrdp_fin_account: changes}

        expect(redirect_url).to eq(wsjrdp_fin_accounts_path(ao: wallet.id))
      end
    end
  end

  it "closes the edit page to the audit tier" do
    sign_in(auditor)

    expect { get :edit, params: {id: wallet.id} }.to raise_error(CanCan::AccessDenied)
  end

  describe "the top-up fields" do
    let(:top_up) do
      {top_up_recipient_name: "Verband e.V.", top_up_iban: "DE16100100101111111111", top_up_bic: "TESTDEFFXXX",
       top_up_purpose: "M000000001"}
    end

    before { sign_in_manage_tier }

    it "are saved on an account without an IBAN" do
      patch :update, params: {id: wallet.id, wsjrdp_fin_account: top_up}

      expect(wallet.reload).to have_attributes(top_up)
    end

    it "are not saved on an account with an IBAN, whatever is sent" do
      patch :update, params: {id: bank.id, wsjrdp_fin_account: {short_name: "Neu", top_up_bic: "TESTDEFFXXX"}}

      expect(bank.reload).to have_attributes(short_name: "Neu", top_up_bic: nil)
    end

    it "are not saved when the same save sets an IBAN" do
      patch :update, params: {id: wallet.id, wsjrdp_fin_account: {iban: "DE02120300000000202051", top_up_bic: "X"}}

      expect(wallet.reload).to have_attributes(iban: "DE02120300000000202051", top_up_bic: nil)
    end

    it "are saved when the same save clears the IBAN" do
      patch :update, params: {id: bank.id, wsjrdp_fin_account: {iban: "", top_up_bic: "TESTDEFFXXX"}}

      expect(bank.reload).to have_attributes(iban: nil, top_up_bic: "TESTDEFFXXX")
    end

    context "on the edit page" do
      render_views

      def inputs = Nokogiri::HTML(response.body).css("input[name^='wsjrdp_fin_account[top_up_']")

      it "are editable on an account without an IBAN" do
        get :edit, params: {id: wallet.id}

        expect(inputs.size).to eq(4)
        expect(inputs.pluck("disabled")).to all(be_nil)
      end

      it "are disabled on an account with an IBAN" do
        get :edit, params: {id: bank.id}

        expect(inputs.size).to eq(4)
        expect(inputs.pluck("disabled")).to all(be_present)
      end
    end
  end
end
