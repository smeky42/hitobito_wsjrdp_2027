# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Moss "Transaktionen" tab: the expandable table over all kinds, the CNF
# filter (Fin::MossTransactionsFilterSchema) in the URL, the PRG apply and the detail.
#
# The table state is exercised through its one-letter params: ?s= sort, ?c=
# columns, ?f= filter, ?z= page size, ?p= page, ?r=1 reset -- plus what this
# page REMEMBERS in the session.
describe Fin::MossTransactionsController do
  # One transaction with one expense and one booking (the uniform shape).
  def create_transaction(type, amount:, **attrs)
    uuid = SecureRandom.uuid
    tx = MossTransaction.create!(type: type, moss_transaction_uuid: uuid,
      signed_total_base_amount: amount, currency: "EUR", payment_date: Date.new(2026, 5, 3),
      booking_date: Date.new(2026, 5, 6),
      transaction_posting_text: "Verpflegung Vortreffen", **attrs)
    expense = MossExpense.create!(moss_transaction: tx, moss_expense_uuid: uuid,
      type: "#{type}Expense", expense_number: 1, signed_expense_base_amount: amount)
    MossBooking.create!(moss_transaction: tx, moss_expense: expense,
      sub_row_number: 1, signed_base_amount: amount,
      account_number: "66500", account_kind: "EXPENSE", cost_center_number: "3100",
      booking_posting_text: "Split eins")
    tx
  end

  before_all(setup_fixtures: true) do
    @person = Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person
    @card = create_transaction("MossCardTransaction", amount: -23.35, merchant_name: "Supermarkt Muster")
    @top_up = create_transaction("MossTopUp", amount: 500, top_up_sender: "Vereinskonto")
  end

  let(:person) { @person }
  let(:card) { @card }
  let(:top_up) { @top_up }

  before { sign_in(person) }

  def rows = controller.transactions

  def shown = rows.page.to_a

  def state = controller.transactions_table_state

  describe "GET index" do
    it "lists every kind" do
      get :index

      expect(response).to be_successful
      expect(shown).to eq([card, top_up])
    end

    it "applies a Rison ?f= filter on the kind" do
      get :index, params: {f: "!(!(!(k,in,MossTopUp)))"}

      expect(shown).to eq([top_up])
    end

    it "narrows the list to the kinds chosen in the Schnellauswahl" do
      get :index, params: {u: "kind.top_up"}

      expect(shown).to eq([top_up])
    end

    it "shows no row with no kind chosen" do
      get :index, params: {u: "kind.-"}

      expect(rows.total_count).to eq(0)
    end

    it "filters on booking-level attributes without duplicating transactions" do
      get :index, params: {f: "!(!(!(acc,in,'66500')))"}

      expect(rows.total_count).to eq(2)
    end

    it "sorts by the ?s= column and direction" do
      get :index, params: {s: "amt~"}

      expect(shown).to eq([top_up, card])
    end

    describe "the date columns" do
      let_it_be(:reimbursement) do
        create_transaction("MossReimbursement", amount: -60, payment_date: nil,
          booking_date: Date.new(2026, 6, 15), transaction_name: "Fahrtkosten Vortreffen")
      end

      it "sorts by the booking date, newest first unless asked" do
        get :index, params: {s: "bdt"}

        expect(shown.last).to eq(reimbursement)
      end

      it "offers the raw payment date as a column of its own, off by default" do
        get :index, params: {c: "bdt,pdt,amt,dsc"}

        expect(state.visible_column_keys).to include("payment_date")
        expect(Fin::MossTransactionsColumns.default_keys).not_to include("payment_date")
      end

      it "is not matched by a Zahlungsdatum filter" do
        get :index, params: {f: "!(!(!(pd,ge,'2026-01-01')))"}

        expect(shown).not_to include(reimbursement)
      end

      it "offers the nullable operators on the Zahlungsdatum attribute" do
        schema = Fin::MossTransactionsFilterSchema.bound
        operators = schema.find(:payment_date).operators.map(&:key)
        expect(operators).to eq(Fin::MossTransactionsFilterSchema::NULLABLE_DATE_OPERATORS)
        expect(operators).to eq(schema.find(:booking_date).operators.map(&:key))
      end
    end

    it "shows exactly the ?c= columns" do
      get :index, params: {c: "pty"}

      expect(state.visible_column_keys).to eq(["party"])
    end

    it "restores the remembered sort on a bare revisit" do
      get :index, params: {s: "amt~"}
      get :index

      expect(shown).to eq([top_up, card])
    end

    it "remembers the filter" do
      get :index, params: {f: "!(!(!(k,in,MossTopUp)))"}
      get :index

      expect(shown).to eq([top_up])
    end

    # A present-but-blank param is the explicit "empty" that beats the store.
    it "clears the remembered filter with an explicitly blank ?f=" do
      get :index, params: {f: "!(!(!(k,in,MossTopUp)))"}
      get :index, params: {f: "", s: "amt~"}
      get :index

      expect(rows.total_count).to eq(2)
    end

    it "forgets everything it remembered on ?r=1" do
      get :index, params: {s: "amt~", f: "!(!(!(k,in,MossTopUp)))"}
      get :index, params: {r: "1"}

      expect(response).to have_http_status(:redirect)
      expect(response.location).to end_with("/fin/moss/transactions")
      get :index
      expect(shown).to eq([card, top_up])
    end

    it "falls back to page 1 when the page is beyond the last one" do
      get :index, params: {z: "1", p: "5"}

      expect(shown).to eq([card])
    end
  end

  # The two amounts of this page -- the transaction total and the "alle Ebenen"
  # search over transaction, expense and booking -- are one picker entry each,
  # with a sign toggle between the signed member and its ABS() twin.
  describe "the amounts and their sign pairs" do
    let(:schema) { Fin::MossTransactionsFilterSchema.bound }

    def compile(tree)
      Wsjrdp::Filtering::Compiler.new(schema)
        .apply(Wsjrdp::Filtering::Query.parse(tree)).to_sql
    end

    # Money leaving the wallet is negative, so only the magnitude finds it.
    it "finds a payment out through |Betrag (Transaktion)|" do
      get :index, params: {f: "!(!(!(amta,bt,20,30)))"}

      expect(shown).to eq([card])
    end

    it "matches any of the three levels through |Betrag (alle Ebenen)|" do
      get :index, params: {f: "!(!(!(amaa,bt,20,30)))"}

      expect(shown).to eq([card])
    end

    it "wraps the transaction column, and all three levels, in ABS()" do
      expect(compile([[["amount_abs", "gte", 100]]]))
        .to include(%(ABS("moss_transactions"."signed_total_base_amount") >= 100))
      sql = compile([[["amount_any_abs", "gte", 100]]])
      expect(sql).to include(%(ABS("moss_transactions"."signed_total_base_amount") >= 100))
        .and include(%(ABS("moss_expenses"."signed_expense_base_amount") >= 100))
        .and include(%(ABS("moss_bookings"."signed_base_amount") >= 100))
      expect(sql.scan("ABS(").size).to eq(3)
      expect(sql).to include(" OR ")
    end

    it "offers the same operator list on all four, the range first" do
      %i[amount amount_abs amount_any amount_any_abs].each do |key|
        expect(schema.find(key).operators.map(&:key)).to eq(%i[between lte gte lt gt eq])
        expect(schema.find(key).pickable_operators.map(&:key)).to eq(%i[between lte gte lt gt eq])
      end
      expect(schema.attributes.values.map(&:short_key)).to include(:amt, :amta, :ama, :amaa)
    end

    # The sign metadata reaches the builder through the catalog -- that is what
    # turns a group's sub-variant dropdown into the ± / |x| toggle.
    it "gives the builder's catalog both pairs" do
      amounts = schema.catalog[:attributes].as_json.select { |a| a["variant_group"].to_s.start_with?("Betrag") }

      expect(amounts.map { |a| [a["key"], a["variant_group"], a["sign"]] }).to eq(
        [["amount", "Betrag (Transaktion)", "signed"],
          ["amount_abs", "Betrag (Transaktion)", "absolute"],
          ["amount_any", "Betrag (alle Ebenen)", "signed"],
          ["amount_any_abs", "Betrag (alle Ebenen)", "absolute"]]
      )
      expect(amounts.pluck("operand_min")).to eq([nil, 0, nil, 0])
    end
  end

  # The kind tabs: the same index, pinned to one kind by the route default.
  # The controller test routes the `kind` param through the kind route, so it
  # arrives as a path parameter -- as in a real request.
  describe "GET index on a kind tab" do
    it "has a route and a tab label for every kind" do
      Fin::MossTransactionsController::KIND_TABS.each_value do |slug|
        expect(Rails.application.routes.url_helpers).to respond_to("moss_#{slug}_path")
        expect(I18n.t("fin.tabs.#{slug}", default: "")).to be_present
      end
      expect(Fin::MossTransactionsController::KIND_TABS.keys).to eq(Fin::MossTransactionsFilterSchema::KINDS)
    end

    it "shows only its kind, with its own columns, without offering the Art attribute" do
      get :index, params: {kind: "MossTopUp"}

      expect(request.path).to eq("/fin/moss/top_ups")
      expect(shown).to eq([top_up])
      expect(state.visible_column_keys).to eq(Fin::MossTransactionsController::KIND_COLUMNS["MossTopUp"][:default])
      expect(state.column_configs([{key: "kind"}])).to be_empty
      expect(state.filter.catalog[:attributes].as_json.pluck("key")).not_to include("kind")
      expect(state.filter.presets).to be_empty
    end

    it "keeps the Art attribute and column on the general tab" do
      get :index

      expect(state.filter.catalog[:attributes].as_json.pluck("key")).to include("kind")
      expect(state.column_configs([{key: "kind"}])).to be_present
    end

    it "remembers each tab's state apart from the others" do
      get :index, params: {kind: "MossCardTransaction", c: "inv"}
      get :index
      expect(state.visible_column_keys).not_to include("invoice_number")

      get :index, params: {kind: "MossCardTransaction"}
      expect(state.visible_column_keys).to include("invoice_number")
    end

    it "ignores a ?kind= query param on the general tab" do
      get :index, params: {kind: "Bogus"}

      expect(request.path).to eq("/fin/moss/transactions")
      expect(controller.current_kind).to be_nil
      expect(rows.total_count).to eq(2)
    end
  end

  describe "expense rows" do
    let_it_be(:reimbursement) do
      tx = MossTransaction.create!(type: "MossReimbursement", moss_transaction_uuid: SecureRandom.uuid,
        currency: "EUR", booking_date: Date.new(2026, 5, 6), signed_total_base_amount: -75.75,
        transaction_name: "Vortreffen Nordlicht")
      [[-45.5, "66910"], [-30.25, "68000"]].each_with_index do |(amount, account), index|
        expense = MossExpense.create!(moss_transaction: tx, type: "MossReimbursementExpense",
          moss_expense_uuid: SecureRandom.uuid, expense_number: index + 1, signed_expense_base_amount: amount)
        MossBooking.create!(moss_transaction: tx, moss_expense: expense, account_kind: "EXPENSE",
          signed_base_amount: amount, sub_row_number: 1, account_number: account, cost_center_number: "2300")
      end
      tx
    end

    # Fin::MossExpenseRowsHelper decides the rows; the table puts them into the
    # transaction's row group, through its own columns.
    context "rendered" do
      render_views

      it "puts one row per Ausgabe between the head row and the detail row, in the shown columns" do
        get :index, params: {c: "bdt,amt,dsc,cc,nb"}

        doc = Nokogiri::HTML(response.body)
        group = doc.css("tbody.exp-group").find { |tbody| tbody.at_css(".exp-detail[data-exp-key='#{reimbursement.id}']") }
        kinds = group.element_children.map { |row| row["class"].to_s.split }
        visible = %w[booking_date signed_total_base_amount description cost_centers bookings_count]
        aggregate_failures do
          expect(kinds.first).to include("exp-row")
          expect(kinds.last).to include("exp-detail-row")
          expect(kinds[1..-2]).to all(include("exp-sub-row"))
          expect(kinds.size).to eq(4)
          expect(group.css("tr.exp-sub-row").map { |row| row.css("td").pluck("data-colkey") }).to eq([visible] * 2)
        end
      end
    end

    # A group travels with its head row and is counted as one transaction.
    it "counts and pages transactions only" do
      get :index, params: {s: "amt", z: "1", p: "1"}

      expect(rows.total_count).to eq(3)
      expect(shown).to eq([reimbursement])
    end
  end

  describe "POST apply" do
    it "redirects to the kind tab it was posted from" do
      post :apply, params: {kind: "MossTopUp", filter_json: "[]"}
      expect(response).to have_http_status(:see_other)
      expect(response.location).to end_with("/fin/moss/top_ups?f=")
    end

    it "redirects (PRG) to the canonical Rison filter URL" do
      post :apply, params: {filter_json: [[["kind", "in", "MossTopUp"]]].to_json}
      expect(response).to have_http_status(:see_other)
      expect(response.location).to end_with("/fin/moss/transactions?f=!(!(!(k,in,'MossTopUp')))")
    end

    # An emptied filter must redirect to an explicitly BLANK param: an absent
    # one would fall through to the remembered filter and bring it straight back.
    it "redirects to a blank filter param when every condition was removed" do
      post :apply, params: {filter_json: "[]"}
      expect(response).to have_http_status(:see_other)
      expect(response.location).to end_with("/fin/moss/transactions?f=")
    end
  end

  describe "GET show" do
    it "shows the transaction" do
      get :show, params: {id: card.id}

      expect(response).to be_successful
      expect(assigns(:transaction)).to eq(card)
    end

    context "rendered" do
      render_views

      # A single expense and booking are said by the fields above.
      it "lists the expenses and the bookings only where there is more than one" do
        get :show, params: {id: card.id}

        expect(Nokogiri::HTML(response.body).css("turbo-frame[data-record^='moss_expense_']")).to be_empty
      end

      it "lists each expense and booking where there are several" do
        second = MossExpense.create!(moss_transaction: card, moss_expense_uuid: SecureRandom.uuid,
          type: "MossCardTransactionExpense", expense_number: 2, signed_expense_base_amount: -3)
        booking = MossBooking.create!(moss_transaction: card, moss_expense: second, sub_row_number: 1,
          signed_base_amount: -3)

        get :show, params: {id: card.id}

        page = Nokogiri::HTML(response.body)
        expect(page.css("turbo-frame[data-record^='moss_expense_']").pluck("src").map { |src| src.split("?").first })
          .to eq([card.expenses.first, second].map { |expense| moss_expense_path(expense) })
        expect(page.at_css("turbo-frame[data-record='moss_booking_#{booking.id}']")).to be_present
      end

      it "gives a row's detail the inline edit form, and the linked person read-only" do
        card.bookings.first.update!(contribution_subject: people(:cmt_leader))
        request.headers["Turbo-Frame"] = "bkframe-mtx-#{card.id}"

        get :show, params: {id: card.id, expandable_table_level: 1}

        frame = Nokogiri::HTML(response.body).at_css("turbo-frame#bkframe-mtx-#{card.id}")
        aggregate_failures do
          expect(frame.at_css("form[action='#{moss_transaction_path(card)}'] textarea[name='moss_transaction[comment]']"))
            .to be_present
          expect(frame.text).to include(people(:cmt_leader).to_s)
          expect(frame.css("a[data-turbo-method]")).to be_empty
        end
      end
    end
  end

  describe "the edit page" do
    it "saves the comment and returns to the reading page" do
      patch :update, params: {id: card.id, moss_transaction: {comment: "Geprüft"}}

      expect(response).to redirect_to(moss_transaction_path(card))
      expect(card.reload.comment).to eq "Geprüft"
    end

    it "brings a save from a row back to the row's detail" do
      request.headers["Turbo-Frame"] = "bkframe-mtx-#{card.id}"
      patch :update, params: {id: card.id, return_url: "/fin/moss", moss_transaction: {comment: "x"}}

      expect(response).to redirect_to(moss_transaction_path(card))
    end

    it "is closed to the read tier" do
      sign_in(Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person)

      expect { get :edit, params: {id: card.id} }.to raise_error(CanCan::AccessDenied)
    end
  end
end
