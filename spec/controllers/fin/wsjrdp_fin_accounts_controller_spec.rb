# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The statement of ONE finance account (/fin/acc/:id). The page serves TWO kinds
# of account and branches on the one marker WsjrdpFinAccount#transactions
# branches on:
#
#   * the MOSS WALLET (transaction_type "MossBalanceMovement") -> the Moss
#     transactions table of the Transaktionen tab, narrowed to this account
#     (the table itself is specced in moss_transactions_controller_spec.rb);
#   * every BANK account -> the plain camt statement it has always been.
#
# Both branches are exercised here; all names, numbers and amounts are invented.
describe Fin::WsjrdpFinAccountsController do
  render_views

  let(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  let!(:wallet) do
    WsjrdpFinAccount.create!(short_name: "Moss-Wallet", account_identification: "MOSS-WALLET-TEST",
      transaction_type: "MossBalanceMovement", opening_balance_cents: 100_000,
      opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
  end

  # One transaction of `type` on the wallet, with its (shell) expense and
  # exactly one booking -- the row the statement shows. `date` is the day the
  # movement was booked in the wallet, which is what the statement is dated by.
  def create_booking(type, amount:, date:, text:, **attrs)
    uuid = SecureRandom.uuid
    transaction = MossTransaction.create!(type: type, moss_transaction_uuid: uuid,
      fin_account: wallet, signed_total_base_amount: amount, currency: "EUR",
      booking_date: date, **attrs)
    expense = MossExpense.create!(moss_transaction: transaction, moss_expense_uuid: uuid,
      type: "#{type}Expense", expense_number: 1, signed_expense_base_amount: amount)
    MossBooking.create!(moss_transaction: transaction, moss_expense: expense,
      sub_row_number: 1, signed_base_amount: amount, booking_posting_text: text)
  end

  # One booking per kind, ordered by Buchungsdatum so the default sort (desc) is
  # top-up, invoice, reimbursement, card. The invoice is the foreign-currency
  # row, the top-up the one with money coming IN.
  let!(:card) do
    create_booking("MossCardTransaction", amount: -25, date: Date.new(2026, 5, 3),
      text: "Split eins", merchant_name: "Muster Markt", card_holder_name: "Vorname Nachname",
      transaction_posting_text: "Verpflegung Vortreffen")
  end

  let!(:reimbursement) do
    create_booking("MossReimbursement", amount: -60, date: Date.new(2026, 6, 1),
      text: "Anteil eins", transaction_name: "Fahrtkosten Vortreffen",
      recipient_name: "Vorname Nachname")
  end

  let!(:invoice) do
    create_booking("MossInvoice", amount: -100, date: Date.new(2026, 7, 15),
      text: "Zeile eins", invoice_number: "RE-2026-1", supplier_account_number: "700027",
      currency_original: "PLN", signed_total_transaction_amount: -425, exchange_rate: 4.25)
  end

  let!(:top_up) do
    create_booking("MossTopUp", amount: 500, date: Date.new(2027, 1, 20),
      text: "Aufladung", top_up_sender: "Vereinskonto")
  end

  before { sign_in(person) }

  def doc = Nokogiri::HTML(response.body)

  def preset_links = doc.css("a.flt-preset")

  describe "GET show of the Moss wallet" do
    # A transaction on another account, which the wallet must not show.
    let!(:elsewhere) do
      other = WsjrdpFinAccount.create!(short_name: "Anderes Wallet", account_identification: "MOSS-OTHER-TEST",
        transaction_type: "MossBalanceMovement", opening_balance_cents: 0,
        opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
      MossTransaction.create!(type: "MossTopUp", moss_transaction_uuid: SecureRandom.uuid, fin_account: other,
        signed_total_base_amount: 7, currency: "EUR", booking_date: Date.new(2026, 8, 1))
    end

    before { get :show, params: {id: wallet.id} }

    it "renders one row per transaction of this account, newest first" do
      expect(response).to be_successful
      expect(doc.css("tbody.exp-group").map { |group| group["class"].to_s.split.grep(/\Amoss-kind-/).first })
        .to eq(%w[MossTopUp MossInvoice MossReimbursement MossCardTransaction]
          .map { |kind| Fin::MossKinds.css_class(kind) })
      expect(response.body).to include("4 Transaktionen").and include("Summe (gefiltert): 315,00\u00A0€")
    end

    it "offers the kinds as one segment, all chosen" do
      expect(doc.css(".flt-segment").size).to eq(1)
      expect(preset_links.pluck("aria-pressed")).to eq(%w[true true true true true])
    end

    # A balance is no transaction, so it sits outside the table: the current
    # one in the page's head line, the opening one below the rows.
    it "keeps the balances outside the table" do
      balances = doc.css(".mw-balance").map { |div| div.text.squish }
      expect(balances.size).to eq(1)
      expect(balances.first).to start_with("Eröffnungs-Saldo")
      # In the money format of the lists (Fin::MoneyHelper).
      expect(balances.first).to end_with(" €")
      expect(doc.css("table .mw-balance")).to be_empty
    end
  end

  describe "the account's head line" do
    let!(:bank) do
      WsjrdpFinAccount.create!(short_name: "Vereinskonto", account_identification: "DE19100100103333333333",
        iban: "DE19100100103333333333", servicer_bic: "GENODEF1TEST", opening_balance_cents: 150_000,
        opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
    end

    def summary = doc.at_css("details.fin-account-summary")

    it "shows name, IBAN and balance, and stays closed by default" do
      get :show, params: {id: bank.id}

      expect(summary["open"]).to be_nil
      line = summary.at_css("summary").text.squish
      expect(line).to include("Vereinskonto", "DE19 1001 0010 3333 3333 33", "1.500,00")
    end

    it "shows the detail with its Bearbeiten link and no form on the page" do
      get :show, params: {id: bank.id}

      expect(summary.css("dl.fin-detail-list").text).to include("GENODEF1TEST", "1.500,00")
      expect(summary.at_css("a[href='#{edit_wsjrdp_fin_account_path(bank)}']").text).to eq("Bearbeiten")
      expect(doc.at_css("input[name='wsjrdp_fin_account[short_name]']")).to be_nil
    end

    it "does not repeat an identification equal to the IBAN" do
      get :show, params: {id: bank.id}

      labels = summary.css("dt").map { |dt| dt.text.squish }
      expect(labels).to include("IBAN")
      expect(labels).not_to include("Konto")
    end

    it "shows a wallet's top-up IBAN, saying what it is" do
      wallet.update!(top_up_iban: "DE16100100101111111111")
      get :show, params: {id: wallet.id}

      expect(summary.at_css("summary").text.squish)
        .to include("Moss-Wallet", "DE16 1001 0010 1111 1111 11 (IBAN für Einzahlungen)")
    end

    it "shows the top-up fields of an account without an IBAN" do
      wallet.update!(top_up_recipient_name: "Verband e.V.", top_up_iban: "DE16100100101111111111",
        top_up_bic: "TESTDEFFXXX", top_up_purpose: "M000000001")
      get :show, params: {id: wallet.id}

      expect(summary.css("dl.fin-detail-list").text).to include("Verband e.V.", "TESTDEFFXXX", "M000000001")
    end

    it "does not show top-up fields left on an account with an IBAN" do
      bank.update!(top_up_bic: "TESTDEFFXXX")
      get :show, params: {id: bank.id}

      expect(summary.css("dl.fin-detail-list").text).not_to include("TESTDEFFXXX")
    end

    it "opens the detail after a save" do
      get :show, params: {id: bank.id, details: "open"}

      expect(summary.key?("open")).to be(true)
    end

    it "offers the IBAN and the BIC for copying, without the spaces of the display" do
      get :show, params: {id: bank.id}

      expect(summary.css("a.fin-copy").pluck("data-copy-to-clipboard"))
        .to eq(["DE19100100103333333333", "GENODEF1TEST"])
    end

    it "offers no copy icon for a value that is not there" do
      bank.update!(servicer_bic: nil)
      get :show, params: {id: bank.id}

      expect(summary.css("a.fin-copy").pluck("data-copy-to-clipboard")).to eq(["DE19100100103333333333"])
    end

    it "links the bookkeeping account in a new tab when it exists" do
      WsjrdpLedgerAccount.create!(number: "18100", name: "Skatbank")
      bank.update!(bookkeeping_account_number: "18100", bookkeeping_account_type: "WsjrdpLedgerAccount")
      get :show, params: {id: bank.id}

      link = summary.at_css("a[target='_blank'][href='#{ledger_account_path("18100")}']")
      expect(link).to be_present
      expect(link.parent.text).to include("18100 Skatbank")
    end

    it "shows a bookkeeping account number that does not exist without a link" do
      bank.update!(bookkeeping_account_number: "99999", bookkeeping_account_type: "WsjrdpLedgerAccount")
      get :show, params: {id: bank.id}

      expect(summary.text).to include("99999")
      expect(summary.css("a[target='_blank']")).to be_empty
    end

    it "opens the form in the detail's frame" do
      get :show, params: {id: bank.id}

      frame = summary.at_css("turbo-frame##{"bkframe-accpage-#{bank.id}"}")
      expect(frame.at_css("a[href='#{edit_wsjrdp_fin_account_path(bank)}']")["data-turbo-frame"]).to eq(frame["id"])
    end

    it "shows the status translated, with the stored value for the write tier" do
      get :show, params: {id: bank.id}

      status = summary.css("dd").find { |dd| dd.text.include?("aktiv") }
      expect(status.at_css("span.text-muted.fw-light").text).to eq("active")
    end

    it "shows the read tier the translated status alone" do
      sign_in(Fabricate(Group::Extern::FinanceAuditor.name.to_sym,
        group: Group::Extern.create!(name: "Extern", parent: groups(:root))).person)
      get :show, params: {id: bank.id}

      expect(summary.css("dd").map { |dd| dd.text.squish }).to include("aktiv")
      expect(summary.text).not_to include("active")
    end

    it "offers the read tier no Bearbeiten link" do
      sign_in(Fabricate(Group::Extern::FinanceAuditor.name.to_sym,
        group: Group::Extern.create!(name: "Extern", parent: groups(:root))).person)
      get :show, params: {id: bank.id}

      expect(response).to be_successful
      expect(summary.at_css("dl.fin-detail-list")).to be_present
      expect(summary.at_css("a[href='#{edit_wsjrdp_fin_account_path(bank)}']")).to be_nil
    end
  end

  describe "GET index" do
    let!(:bank) do
      WsjrdpFinAccount.create!(short_name: "Vereinskonto", account_identification: "DE19100100103333333333",
        iban: "DE19100100103333333333", opening_balance_cents: 10_000, opening_balance_currency: "EUR",
        opening_balance_date: Date.new(2026, 1, 1))
    end

    let!(:closed) do
      WsjrdpFinAccount.create!(short_name: "Altes Konto", account_identification: "ALT-1", status: "closed",
        opening_balance_cents: 2_500, opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
    end

    before do
      WsjrdpCamtTransaction.create!(fin_account: bank, camt_type: "CAMT053",
        account_identification: bank.account_identification, account_servicer_reference: "REF-IDX",
        credit_debit_indication: "DBIT", signed_base_amount: -12.34, base_currency: "EUR",
        value_date: Date.new(2026, 4, 2), description: "Beispielbuchung")
    end

    def row_of(account) = doc.at_css("tr.exp-row[data-key='#{account.id}']") || doc.css("tr.exp-row").find { |tr| tr.text.include?(account.short_name) }

    it "lists every account as an expandable row with the balance of its statement" do
      get :index

      expect(row_of(bank).text.squish).to include("Vereinskonto", "DE19 1001 0010 3333 3333 33", "87,66")
      expect(row_of(bank).at_css("a[href='#{wsjrdp_fin_account_path(bank)}']").text).to eq("Vereinskonto")
      expect(row_of(closed).text.squish).to include("Altes Konto", "geschlossen", "25,")
      expect(row_of(closed)["class"]).to include("text-muted")
    end

    it "loads the stream actions a save from a row answers with" do
      get :index

      expect(doc.at_css("script[src*='turbo_stream_actions']")).to be_present
    end

    it "loads the account's detail into the row" do
      get :index

      expect(response.body).to include(wsjrdp_fin_account_path(bank))
      expect(doc.css("turbo-frame[id^='bkframe-acc-']").pluck("src"))
        .to include(wsjrdp_fin_account_path(bank, expandable_table_level: 1))
    end

    it "offers the columns menu, with Kontoart in it but not shown" do
      get :index

      expect(doc.css("thead th").map { |th| th.text.squish }.join(" ")).not_to include("Kontoart")
      expect(response.body).to include("Kontoart")
    end

    it "shows Kontoart once picked in the columns menu" do
      get :index, params: {ac: "lb,pr,sa"}

      expect(doc.css("thead th").map { |th| th.text.squish }.join(" ")).to include("Konto", "Kontoart", "Saldo")
    end

    it "sums the balances in the footer" do
      get :index

      # The wallet of the outer let! (1.000,00 € and its four bookings: 1.315,00 €), the
      # bank (87,66 €), the closed account (25,00 €).
      expect(doc.css("tfoot").text.squish).to include("Summe", "1.427,66")
    end

    # Only this spec's accounts: a database built by the migrations also has
    # the "Moss Wallet" a migration creates (balance 0).
    it "sorts by the balance" do
      get :index, params: {as: "sa~"}

      ours = doc.css("tr.exp-row").map { |tr| tr.text.squish }
        .select { |text| text.start_with?("Moss-Wallet", "Vereinskonto", "Altes Konto") }
      expect(ours).to match([start_with("Moss-Wallet"), start_with("Vereinskonto"), start_with("Altes Konto")])
    end
  end

  describe "the detail in a row of the list" do
    let(:frame_id) { "bkframe-acc-#{wallet.id}" }

    before { request.headers["Turbo-Frame"] = frame_id }

    it "answers the row's frame with the detail and its Bearbeiten in that frame" do
      get :show, params: {id: wallet.id}

      frame = doc.at_css("turbo-frame##{frame_id}")
      expect(frame.at_css("dl.fin-detail-list")).to be_present
      expect(frame.at_css("a[href='#{edit_wsjrdp_fin_account_path(wallet)}']")["data-turbo-frame"]).to eq(frame_id)
      expect(response.body).not_to include("Eröffnungs-Saldo</span>")
      expect(doc.css("tr.exp-row")).to be_empty
    end

    it "opens the form in the row's frame" do
      get :edit, params: {id: wallet.id}

      expect(doc.at_css("turbo-frame##{frame_id} input[name='wsjrdp_fin_account[short_name]']")).to be_present
    end

    it "answers a save by reloading the list with the row open" do
      request.accept = "text/vnd.turbo-stream.html, text/html"
      patch :update, params: {id: wallet.id, wsjrdp_fin_account: {short_name: "Neuer Name"}}

      expect(doc.at_css("turbo-stream[action='redirect_top']")["url"]).to eq(wsjrdp_fin_accounts_path(ao: wallet.id))
    end
  end

  describe "GET edit" do
    it "puts Speichern and Abbrechen once, in the sticky line above the fields" do
      get :edit, params: {id: wallet.id}

      expect(doc.css("button[type=submit]").count { |b| b.ancestors("form").first&.at_css("input[name='wsjrdp_fin_account[short_name]']") }).to eq(1)
      expect(doc.at_css(".fin-account-form-actions button[type=submit]")).to be_present
      expect(doc.at_css(".fin-account-form-actions a.cancel")).to be_present
    end

    it "shows the account's form as a page of its own" do
      get :edit, params: {id: wallet.id}

      expect(response).to be_successful
      expect(doc.at_css("form input[name='wsjrdp_fin_account[short_name]']")).to be_present
      expect(doc.at_css("turbo-frame#bkframe-accpage-#{wallet.id}")).to be_nil
      form = doc.at_css("input[name='wsjrdp_fin_account[short_name]']").ancestors("form").first
      expect(form["data-turbo"]).to eq("false")
    end

    it "answers a frame request with the form in the frame, cancelling to the reading view" do
      frame_id = "bkframe-accpage-#{wallet.id}"
      request.headers["Turbo-Frame"] = frame_id
      get :edit, params: {id: wallet.id}

      frame = doc.at_css("turbo-frame##{frame_id}")
      expect(frame.at_css("input[name='wsjrdp_fin_account[short_name]']")).to be_present
      expect(frame.at_css("form")["data-turbo"]).to be_nil
      expect(frame.at_css("a.cancel")["href"]).to eq(wsjrdp_fin_account_path(wallet))
    end

    context "with the top-up block" do
      let(:bank_with_iban) do
        WsjrdpFinAccount.create!(short_name: "Bank", account_identification: "DE02120300000000202051",
          iban: "DE02120300000000202051", opening_balance_cents: 0, opening_balance_currency: "EUR",
          opening_balance_date: Date.new(2026, 1, 1))
      end

      def top_up_inputs
        %w[top_up_recipient_name top_up_iban top_up_bic top_up_purpose].map { |attr| doc.at_css("input[name='wsjrdp_fin_account[#{attr}]']") }
      end

      def sign_in_manager
        sign_in(Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person)
        # The manage tier only takes effect once picked for the session.
        session[:max_finance_permission] = "finance_manage"
      end

      it "is editable for the manage tier on an account without an IBAN" do
        sign_in_manager
        get :edit, params: {id: wallet.id}

        expect(response.body).to include(I18n.t("fin.accounts.top_up_hint"))
        expect(top_up_inputs).to all(be_present)
        expect(top_up_inputs.pluck("disabled")).to all(be_nil)
      end

      it "is disabled for the manage tier on an account with an IBAN" do
        sign_in_manager
        get :edit, params: {id: bank_with_iban.id}

        expect(response.body).to include(I18n.t("fin.accounts.top_up_disabled_hint"))
        expect(top_up_inputs.pluck("disabled")).to all(be_present)
      end

      it "is read-only below the manage tier on an account without an IBAN" do
        get :edit, params: {id: wallet.id}

        expect(response.body).to include(I18n.t("fin.accounts.top_up_hint"))
        expect(top_up_inputs).to all(be_nil)
      end

      it "is not there below the manage tier on an account with an IBAN" do
        get :edit, params: {id: bank_with_iban.id}

        expect(response.body).not_to include(WsjrdpFinAccount.human_attribute_name(:top_up_bic))
        expect(response.body).not_to include(I18n.t("fin.accounts.top_up_disabled_hint"))
      end

      it "saves the fields on an account without an IBAN" do
        sign_in_manager
        patch :update, params: {id: wallet.id, wsjrdp_fin_account: {top_up_recipient_name: "Verband e.V.",
                                                                    top_up_iban: "DE16100100101111111111",
                                                                    top_up_bic: "TESTDEFFXXX", top_up_purpose: "M000000001"}}

        expect(wallet.reload).to have_attributes(top_up_recipient_name: "Verband e.V.",
          top_up_iban: "DE16100100101111111111", top_up_bic: "TESTDEFFXXX", top_up_purpose: "M000000001")
      end

      it "does not save the fields on an account with an IBAN, whatever is sent" do
        sign_in_manager
        patch :update, params: {id: bank_with_iban.id, wsjrdp_fin_account: {short_name: "Neu", top_up_bic: "TESTDEFFXXX"}}

        expect(bank_with_iban.reload).to have_attributes(short_name: "Neu", top_up_bic: nil)
      end

      it "does not save the fields when the same save sets an IBAN" do
        sign_in_manager
        patch :update, params: {id: wallet.id, wsjrdp_fin_account: {iban: "DE02120300000000202051", top_up_bic: "TESTDEFFXXX"}}

        expect(wallet.reload).to have_attributes(iban: "DE02120300000000202051", top_up_bic: nil)
      end

      it "saves the fields when the same save clears the IBAN" do
        sign_in_manager
        patch :update, params: {id: bank_with_iban.id, wsjrdp_fin_account: {iban: "", top_up_bic: "TESTDEFFXXX"}}

        expect(bank_with_iban.reload).to have_attributes(iban: nil, top_up_bic: "TESTDEFFXXX")
      end
    end

    it "is closed to the read tier" do
      sign_in(Fabricate(Group::Extern::FinanceAuditor.name.to_sym,
        group: Group::Extern.create!(name: "Extern", parent: groups(:root))).person)

      expect { get :edit, params: {id: wallet.id} }.to raise_error(CanCan::AccessDenied)
    end
  end

  describe "PATCH update" do
    it "saves and returns to the reading page" do
      patch :update, params: {id: wallet.id, wsjrdp_fin_account: {short_name: "Neuer Name"}}

      expect(response).to redirect_to(wsjrdp_fin_account_path(wallet, details: "open"))
      expect(wallet.reload.short_name).to eq("Neuer Name")
    end

    it "shows the edit page again when the record is invalid" do
      allow_any_instance_of(WsjrdpFinAccount).to receive(:save).and_return(false)
      patch :update, params: {id: wallet.id, wsjrdp_fin_account: {short_name: "Neu"}}

      expect(response).to have_http_status(:bad_request)
      expect(doc.at_css("form input[name='wsjrdp_fin_account[short_name]']")).to be_present
    end

    context "from the detail's frame" do
      let(:frame_id) { "bkframe-accpage-#{wallet.id}" }

      before do
        request.headers["Turbo-Frame"] = frame_id
        request.accept = "text/vnd.turbo-stream.html, text/html"
      end

      it "answers a save by leaving the frame for the page with the detail open" do
        patch :update, params: {id: wallet.id, wsjrdp_fin_account: {short_name: "Neuer Name"}}

        stream = doc.at_css("turbo-stream[action='redirect_top']")
        expect(stream["url"]).to eq(wsjrdp_fin_account_path(wallet, details: "open"))
        expect(wallet.reload.short_name).to eq("Neuer Name")
      end

      it "keeps a failed save in the frame, with its errors" do
        wallet.errors.add(:base, "Kaputt")
        allow_any_instance_of(WsjrdpFinAccount).to receive(:save).and_return(false)
        patch :update, params: {id: wallet.id, wsjrdp_fin_account: {short_name: "Neu"}}

        expect(response).to have_http_status(:bad_request)
        frame = doc.at_css("turbo-frame##{frame_id}")
        expect(frame.at_css("input[name='wsjrdp_fin_account[short_name]']")["value"]).to eq("Neu")
      end
    end
  end

  describe "POST apply" do
    it "encodes the posted tree and redirects (PRG) back to this account" do
      post :apply, params: {id: wallet.id, filter_json: [[["kind", "in", "MossTopUp"]]].to_json}
      expect(response).to have_http_status(:see_other)
      expect(CGI.unescape(response.location))
        .to end_with("/fin/acc/#{wallet.id}?f=!(!(!(k,in,'MossTopUp')))")
    end

    it "emits a blank filter param when every condition was removed" do
      post :apply, params: {id: wallet.id, filter_json: "[]"}
      expect(response).to have_http_status(:see_other)
      expect(response.location).to end_with("/fin/acc/#{wallet.id}?f=")
    end
  end

  # The other branch of the same template: a bank account keeps the plain camt
  # table, unchanged -- no filter, no presets, no kind marking, and the info
  # icon it has always had.
  describe "GET show of a bank account" do
    let!(:bank) do
      WsjrdpFinAccount.create!(short_name: "Vereinskonto", account_identification: "BANK-TEST",
        opening_balance_cents: 0, opening_balance_currency: "EUR",
        opening_balance_date: Date.new(2026, 1, 1))
    end

    let!(:camt) do
      WsjrdpCamtTransaction.create!(fin_account: bank, camt_type: "CAMT053",
        account_identification: bank.account_identification, account_servicer_reference: "REF-1",
        credit_debit_indication: "DBIT", signed_base_amount: -12.34, base_currency: "EUR",
        value_date: Date.new(2026, 4, 2), description: "Beispielbuchung")
    end

    it "renders the camt statement" do
      get :show, params: {id: bank.id}
      expect(response).to be_successful
      expect(response.body).to include("Beispielbuchung").and include("Eröffnungs-Saldo")
      expect(doc.at_css("details.fin-account-summary summary").text).to include("-12,34")
      expect(doc.css("a[href='#{wsjrdp_camt_transaction_path(camt)}'] span.fa-info-circle")).to be_present
      expect(response.body).not_to include("flt-preset")
      expect(response.body).not_to include("moss-kind")
      expect(doc.css("tr.exp-row")).to be_empty
    end
  end
end
