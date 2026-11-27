# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Kreditoren page: the relation-backed Buchhaltung summary with its filter
# and footer totals, a Kreditor's detail and the Unit-Budget flag it edits.
describe Fin::PersonalAccountsController do
  before_all(setup_fixtures: true) {}

  let_it_be(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let_it_be(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }

  # 700101 aktiv, balance 30 over 2 bookings; 700102 inaktiv, balance -50 over
  # 1; 700103 Moss-unknown (NULL -> inaktiv), no booking; 700104 aktiv, no
  # booking. Order by number, by sum and by count all differ. The creditor is
  # the Konto, so the leg is +amount for "D", -amount for "C".
  before_all do
    {"700101" => "active", "700102" => "deactivated", "700103" => nil, "700104" => "active"}.each do |number, status|
      WsjrdpPersonalAccount.create!(number: number, name: "Kreditor #{number}", account_kind: "CREDITOR",
        moss_status: status)
    end
    [["700101", 100, "D"], ["700101", 70, "C"], ["700102", 50, "C"]].each do |number, amount, debit_credit|
      DatevBooking.create!(buchungs_guid: SecureRandom.uuid, account_number: number, account_kind: "CREDITOR",
        offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
        base_amount: amount, transaction_amount: amount, debit_credit: debit_credit,
        base_currency: "EUR", booking_date: Date.new(2026, 2, 1), posting_text: "Testbuchung #{number}")
    end
  end

  before { sign_in(person) }

  def listed = controller.personal_accounts.page.map(&:number)

  def unit_budget(number) = WsjrdpPersonalAccount.find_by(number: number).is_unit_budget

  describe "GET index" do
    it "lists every Kreditor by number and counts their bookings" do
      get :index

      expect(listed).to eq(%w[700101 700102 700103 700104])
      expect(controller.shown_booking_count).to eq(3)
    end

    it "narrows by the filter and counts the bookings of what is left" do
      get :index, params: {f: "!(!(!(bc,gt,0)))"}

      expect(listed).to eq(%w[700101 700102])
      expect(controller.shown_booking_count).to eq(3)
    end

    it "sorts by the balance" do
      get :index, params: {s: "bb"}

      expect(listed).to eq(%w[700102 700103 700104 700101])
    end

    it "sorts by the Moss status, a NULL status as inaktiv" do
      get :index, params: {s: "ms,nr"}

      expect(listed).to eq(%w[700101 700104 700102 700103])
    end

    it "remembers the filter on a bare revisit and clears it on a blank ?f=" do
      get :index, params: {f: "!(!(!(bc,gt,0)))"}
      expect(listed).to eq(%w[700101 700102])
      get :index
      expect(listed).to eq(%w[700101 700102])

      get :index, params: {f: ""}
      expect(listed).to eq(%w[700101 700102 700103 700104])
    end
  end

  describe "POST apply" do
    it "encodes the posted tree into the filter param and redirects (PRG)" do
      post :apply, params: {filter_json: [[["booking_count", "gt", 0]]].to_json}

      expect(response).to have_http_status(:see_other)
      expect(CGI.unescape(response.location)).to end_with("/fin/bookkeeping/personal_accounts?f=!(!(!(bc,gt,0)))")
    end
  end

  describe "GET show" do
    it "shows the Kreditor with the bookings on either side of it" do
      get :show, params: {number: "700101"}

      expect(assigns(:account)).to be_persisted
      expect(assigns(:ctx)).to be_regular
      expect(controller.send(:supplier_bookings, "700101").total_count).to eq(2)
    end

    it "answers a list row's frame with the embedded detail" do
      request.headers["Turbo-Frame"] = "bkframe-supplier-700101"
      get :show, params: {number: "700101", expandable_table_level: "1"}

      expect(assigns(:ctx)).to be_embedded
    end

    it "shows a number without master data as a stub record" do
      get :show, params: {number: "799999"}

      expect(assigns(:account)).to be_new_record
      expect(assigns(:account).number).to eq("799999")
    end

    it "lets the read tier read" do
      sign_in(reader)
      get :show, params: {number: "700101"}

      expect(response).to have_http_status(:ok)
    end
  end

  describe "the Unit-Budget flag" do
    it "flips and goes on to the reading page" do
      patch :update, params: {number: "700101", wsjrdp_personal_account: {is_unit_budget: "false", name: "Neu"}}

      expect(response).to redirect_to(personal_account_path("700101"))
      expect(WsjrdpPersonalAccount.find_by(number: "700101")).to have_attributes(is_unit_budget: false,
        name: "Kreditor 700101")
    end

    it "is closed to the read tier" do
      sign_in(reader)

      expect { get :edit, params: {number: "700101"} }.to raise_error(CanCan::AccessDenied)
      expect { patch :update, params: {number: "700101", wsjrdp_personal_account: {is_unit_budget: "false"}} }
        .to raise_error(CanCan::AccessDenied)
      expect(unit_budget("700101")).to be true
    end

    it "has no edit page for a number without master data" do
      expect { get :edit, params: {number: "700999"} }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
