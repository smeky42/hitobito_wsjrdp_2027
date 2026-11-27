# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Sachkonten summary, as the representative of the three Buchhaltung summary
# pages (they share Fin::BookkeepingSummaries): the relation-backed list
# (WsjrdpLedgerAccount.with_booking_summary) with its footer totals over the
# filtered set, its visibility rule and the bookings table embedded in an
# account's detail.
describe Fin::LedgerAccountsController do
  before_all(setup_fixtures: true) {}

  let_it_be(:person, refind: true) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let_it_be(:reader, refind: true) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }

  # Invented numbers and names. `visibility: "visible"` keeps the fabricated
  # accounts out of the page's own visibility rule -- that rule has its own
  # describe block below.
  def self.create_account(number, name, kind, short_name: nil, moss_status: nil, visibility: "visible")
    WsjrdpLedgerAccount.create!(number: number, name: name, short_name: short_name,
      account_kind: kind, moss_status: moss_status, visibility: visibility)
  end

  def self.create_booking(account, kind, offsetting, offsetting_kind, amount, debit_credit)
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: account, account_kind: kind,
      offsetting_account_number: offsetting, offsetting_account_kind: offsetting_kind,
      base_amount: amount, transaction_amount: amount, debit_credit: debit_credit,
      booking_date: Date.new(2026, 3, 1), posting_text: "Testbuchung #{account}")
  end

  delegate :create_account, :create_booking, to: :class

  # Three accounts whose order by number and order by sum deliberately differ, so
  # a sort assertion cannot pass by accident. Two bookings, each counting on BOTH
  # its sides: 1200 sees two of them, 4000 and 66500 one each.
  before_all do
    create_account("1200", "Testbank", "BANK", short_name: "Bankkonto", moss_status: "active")
    create_account("4000", "Testerloese", "INCOME", moss_status: "deactivated")
    create_account("66500", "Testaufwand", "EXPENSE", short_name: "Kostenkurz")
    create_booking("1200", "BANK", "66500", "EXPENSE", 100, "D")
    create_booking("1200", "BANK", "4000", "INCOME", 300, "C")
  end

  before { sign_in(person) }

  def rendered_numbers = controller.ledger_accounts.page.map(&:number)

  def column_keys = controller.summary_table_state.visible_column_keys

  describe "GET index" do
    it "lists the visible accounts by number and totals them in the footer" do
      get :index

      aggregate_failures do
        expect(response).to be_successful
        expect(rendered_numbers).to eq(%w[1200 4000 66500])
        expect(controller.ledger_accounts.total_count).to eq(3)
        expect(controller.shown_booking_count).to eq(4)
        expect(controller.shown_booking_sum).to eq(-400)
      end
    end

    it "sorts by the state's ?s= param, using the column's wire token" do
      get :index, params: {s: "sum~"}
      expect(rendered_numbers).to eq(%w[66500 1200 4000])
    end

    it "sorts on the Kurzbezeichnung, NULLS LAST" do
      get :index, params: {s: "kbz"}
      expect(rendered_numbers).to eq(%w[1200 66500 4000])
    end

    it "sorts on the Moss status, aktiv before inaktiv and NULL as inaktiv" do
      get :index, params: {s: "ms,nr"}
      expect(rendered_numbers).to eq(%w[1200 4000 66500])
    end

    it "selects and orders the columns from ?c=" do
      get :index, params: {c: "sum,nr,~bez"}
      expect(column_keys).to eq(%w[booking_sum number])
    end

    it "offers the Unit-Budget as a column, not shown by default" do
      get :index, params: {c: "nr,ub"}

      aggregate_failures do
        expect(Fin::BookkeepingSummaryColumns::LEDGER_ACCOUNTS.default_keys).not_to include("is_unit_budget")
        expect(column_keys).to eq(%w[number is_unit_budget])
      end
    end

    it "falls back to page 1 when the page is beyond the last one (D4)" do
      get :index, params: {z: "1", p: "999"}
      expect(rendered_numbers).to eq(%w[1200])
    end

    it "redirects to the bare URL on ?r=1" do
      get :index, params: {r: "1"}
      expect(response).to redirect_to("/fin/bookkeeping/ledger_accounts")
    end

    it "narrows on a filter and totals the footer over what is left" do
      get :index, params: {f: "!(!(!(ak,in,'BANK')))"}

      aggregate_failures do
        expect(rendered_numbers).to eq(%w[1200])
        expect(controller.shown_booking_count).to eq(2)
        expect(controller.shown_booking_sum).to eq(-200)
      end
    end
  end

  # Which accounts the list shows at all (Fin::LedgerAccountsController's own
  # visibility rule, not a filter): `visible` always, `hidden` never, `auto` only
  # when Moss knows the account as active or it carries a booking. Personal
  # accounts are no Sachkonten and have their own page.
  describe "GET index, the visibility rule" do
    it "hides an unbooked auto account Moss does not know as active" do
      create_account("2000", "Testauto", "EXPENSE", visibility: "auto", moss_status: "deactivated")
      get :index
      expect(rendered_numbers).not_to include("2000")
    end

    it "shows an auto account Moss knows as active" do
      create_account("2000", "Testauto", "EXPENSE", visibility: "auto", moss_status: "active")
      get :index
      expect(rendered_numbers).to include("2000")
    end

    it "shows a booked auto account" do
      create_account("2000", "Testauto", "EXPENSE", visibility: "auto", moss_status: "deactivated")
      create_booking("1200", "BANK", "2000", "EXPENSE", 10, "D")
      get :index
      expect(rendered_numbers).to include("2000")
    end

    it "never shows a hidden account and never a Personenkonto" do
      create_account("2100", "Testverborgen", "EXPENSE", visibility: "hidden", moss_status: "active")
      create_account("3100", "Testkreditor", "CREDITOR")
      get :index
      expect(rendered_numbers).to eq(%w[1200 4000 66500])
    end

    # An account the LIST leaves out still has its detail page.
    it "still shows the detail page of an account it leaves out" do
      create_account("2100", "Testverborgen", "EXPENSE", visibility: "hidden")
      get :show, params: {number: "2100"}

      expect(response).to be_successful
      expect(assigns(:account)).to be_persisted
    end
  end

  describe "POST apply" do
    it "encodes the posted tree into the filter param and redirects (PRG)" do
      post :apply, params: {filter_json: [[["account_kind", "in", "BANK"]]].to_json}
      expect(response).to have_http_status(:see_other)
      expect(CGI.unescape(response.location))
        .to end_with("/fin/bookkeeping/ledger_accounts?f=!(!(!(ak,in,'BANK')))")
    end

    it "emits a blank filter param when nothing survives" do
      post :apply, params: {filter_json: [[["nope", "in", "x"]]].to_json}
      expect(response.location).to end_with("?f=")
    end
  end

  describe "GET show" do
    # The embedded bookings table is legs-backed (DatevBooking.legs), a derived
    # table aliased back to `datev_bookings`; the Unit-Budget columns compose
    # with it.
    it "answers the Unit-Budget in the account's own embedded bookings" do
      WsjrdpLedgerAccount.find_by(number: "66500").update!(is_unit_budget: false)
      get :show, params: {number: "1200"}

      expect(controller.send(:account_bookings, "1200").page.map { |b| b.unit_budget.first })
        .to match_array([false, true])
    end

    # The embedded table lives under the "b" prefix and keeps the nesting level
    # the summary list put into the frame URL.
    it "renders a lazily loaded detail row as an embedded detail at its level" do
      request.headers["Turbo-Frame"] = "bkframe-account-1200"
      get :show, params: {number: "1200", expandable_table_level: "1"}

      aggregate_failures do
        expect(assigns(:ctx)).to be_embedded
        expect(controller.summary_table_state.level).to eq(1)
        expect(controller.item_bookings_table_state.level).to eq(1)
      end
    end

    it "remembers the embedded table's sort per account (D2)" do
      get :show, params: {number: "1200", bs: "amt"}
      store_key = Fin::BookkeepingSummaries.item_bookings_policy_options(row_param: :number)[:store_key]

      aggregate_failures do
        expect(controller.instance_exec(&store_key)).to eq("fin/ledger_accounts#show:1200")
        expect(controller.item_bookings_table_state.sort_list).to eq([["signed_base_amount", "asc"]])
      end
    end

    describe "the reading page" do
      render_views

      def doc = Nokogiri::HTML(response.body)

      def link(text) = doc.css("a").find { |a| a.text.strip == text }

      # "In Buchungen-Ansicht öffnen" leads to the Buchungen listing pinned to
      # this account on either side, "Konto oder Gegenkonto" (kgk), because the
      # embedded list shows both booking sides.
      it "leads the write tier to the edit page and to the Buchungen of this account" do
        get :show, params: {number: "1200"}

        aggregate_failures do
          expect(link("Bearbeiten")["href"]).to eq(edit_ledger_account_path("1200"))
          expect(CGI.unescapeHTML(link("In Buchungen-Ansicht öffnen")["href"]))
            .to eq("/fin/bookkeeping/bookings?f=!(!(!(kgk,in,'1200')))")
        end
      end

      it "offers the read tier no way to edit" do
        sign_in(reader)
        get :show, params: {number: "1200"}

        expect(link("Bearbeiten")).to be_nil
      end
    end
  end

  # Whether a booking on this account belongs to a unit's budget: the one field
  # of a Sachkonto Hitobito owns. It is edited on a page of its own.
  describe "editing the Unit-Budget" do
    it "renders the edit page for the write tier" do
      get :edit, params: {number: "1200"}
      expect(response).to be_successful
    end

    it "flips the flag and goes on to the reading page" do
      patch :update, params: {number: "1200", wsjrdp_ledger_account: {is_unit_budget: "false"}}

      expect(response).to redirect_to(ledger_account_path("1200"))
      expect(WsjrdpLedgerAccount.find_by(number: "1200").is_unit_budget).to be false
    end

    it "refuses the read tier the edit page" do
      sign_in(reader)
      expect { get :edit, params: {number: "1200"} }.to raise_error(CanCan::AccessDenied)
    end

    it "refuses the read tier the update" do
      sign_in(reader)

      expect do
        patch :update, params: {number: "1200", wsjrdp_ledger_account: {is_unit_budget: "false"}}
      end.to raise_error(CanCan::AccessDenied)
      expect(WsjrdpLedgerAccount.find_by(number: "1200").is_unit_budget).to be true
    end

    # #show invents a stub record for a number without master data; there is
    # nothing to edit on one, so #edit answers 404 instead.
    it "has no edit page for a number without master data" do
      expect { get :edit, params: {number: "999999"} }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
