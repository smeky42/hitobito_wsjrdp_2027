# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Fin::AccountingEntriesController, type: :controller do
  before_all(setup_fixtures: true) {}

  let_it_be(:manager) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }
  let(:person) { people(:yp_a_1) }

  let_it_be(:entry, refind: true) do
    AccountingEntry.create!(subject: people(:yp_a_1), author: manager,
      amount_cents: 10_000, amount_currency: "EUR",
      description: "Beitragsrate", value_date: Date.new(2026, 3, 1),
      booking_date: Date.new(2026, 3, 1))
  end

  before do
    sign_in(manager)
    # The manage tier has to be picked for the session.
    session[:max_finance_permission] = "finance_manage"
  end

  def last_booking = AccountingEntry.order(:id).last

  def errors = assigns(:accounting_entry).errors

  describe "the fee reconciliation flag" do
    it "is offered to the manage tier" do
      get :edit, params: {id: entry.id}

      expect(controller.permitted_attrs).to include(:excluded_from_fee_reconciliation)
    end

    it "is left out below the manage tier" do
      session[:max_finance_permission] = "finance"
      get :edit, params: {id: entry.id}

      expect(controller.permitted_attrs).not_to include(:excluded_from_fee_reconciliation)
    end

    it "stores a checked box as the boolean true" do
      put :update, params: {id: entry.id, accounting_entry: {excluded_from_fee_reconciliation: "1"}}

      expect(entry.reload.additional_info).to eq("excluded_from_fee_reconciliation" => true)
      expect(AccountingEntry.excluded_from_fee_reconciliation).to include(entry)
    end

    # Stored as a string, "0" would read as true.
    it "drops the key again when the box is unchecked" do
      entry.update!(excluded_from_fee_reconciliation: true)

      put :update, params: {id: entry.id, accounting_entry: {excluded_from_fee_reconciliation: "0"}}

      expect(entry.reload.additional_info).to eq({})
      expect(AccountingEntry.fee_reconciliation_relevant).to include(entry)
    end
  end

  describe "the status-change booking" do
    before { person.update!(sepa_status: "ok") }

    def statuses_on_offer = controller.selectable_sepa_statuses.keys.map(&:to_s)

    it "leaves the person's current status out of the select" do
      get :new_sepa_status, params: {accounting_entry: {subject_id: person.id}}

      expect(statuses_on_offer).to match_array(Settings.sepa_status.to_h.keys.map(&:to_s) - ["ok"])
    end

    it "offers every status without a person" do
      get :new_sepa_status

      expect(statuses_on_offer).to match_array(Settings.sepa_status.to_h.keys.map(&:to_s))
    end

    it "books nothing and stays out of the reconciliation" do
      expect do
        post :new_sepa_status, params: {accounting_entry: {subject_id: person.id, new_sepa_status: "in_review"}}
      end.to change { AccountingEntry.count }.by(1)

      expect(last_booking.amount_cents).to eq(0)
      expect(last_booking).to be_excluded_from_fee_reconciliation
      expect(person.reload.sepa_status).to eq("in_review")
    end

    it "keeps the flag against anything the request sends" do
      post :new_sepa_status, params: {accounting_entry: {subject_id: person.id, new_sepa_status: "missing",
                                                         amount_cents: 5000, excluded_from_fee_reconciliation: "0"}}

      expect(last_booking.amount_cents).to eq(0)
      expect(last_booking).to be_excluded_from_fee_reconciliation
    end

    it "asks for the person back on the form" do
      post :new_sepa_status, params: {accounting_entry: {new_sepa_status: "in_review"}}

      expect(response).to have_http_status(:bad_request)
      expect(errors[:subject_id]).to be_present
      expect(person.reload.sepa_status).to eq("ok")
    end

    it "asks for the status the same way" do
      expect do
        post :new_sepa_status, params: {accounting_entry: {subject_id: person.id, new_sepa_status: ""}}
      end.not_to change(AccountingEntry, :count)

      expect(response).to have_http_status(:bad_request)
      expect(errors[:new_sepa_status]).to be_present
    end
  end

  describe "creating a booking" do
    def create(**params)
      post :create, params: {accounting_entry: {subject_id: person.id, amount_eur: "12.34",
                                                description: "Testbuchung"}, **params}
    end

    it "creates a booking for the person picked in the bare form and leads to it" do
      expect { create }.to change { AccountingEntry.count }.by(1)

      expect(last_booking).to have_attributes(subject: person, amount_cents: 1234)
      expect(response).to redirect_to(last_booking)
    end

    it "refreshes the page around the frame instead" do
      request.headers["Turbo-Frame"] = "accounting_extra_entry"

      create

      expect(response.body).to include('action="refresh"')
    end
  end

  it "lists the bookings without an entry to ask about" do
    get :index

    expect(response).to be_successful
  end

  # The forms opened without parameters ask for the person; a page that knows
  # it may hide it.
  describe "the person on the new forms" do
    render_views

    def doc = Nokogiri::HTML(response.body)

    def person_picker = doc.at_css("[data-provide=entity][data-id-field=accounting_entry_subject_id]")

    def person_row = doc.text.squish[/Person\s*#{Regexp.escape(person.to_s)}/]

    it "asks for the person on the booking form" do
      get :new

      expect(person_picker).to be_present
    end

    it "asks for the person on the status form" do
      get :new_sepa_status

      expect(person_picker).to be_present
    end

    it "shows the name instead of the picker once the subject is known" do
      get :new, params: {accounting_entry: {subject_id: person.id}}

      expect(person_picker).to be_nil
      expect(person_row).to be_present
    end

    it "leaves the person out of the form when the page asks for it, keeping the id" do
      get :new, params: {accounting_entry: {subject_id: person.id}, hide_subject: 1}

      expect(person_row).to be_nil
      expect(doc.at_css("#accounting_entry_subject_id")["value"]).to eq(person.id.to_s)
      expect(doc.at_css("input[name=hide_subject]")).to be_present
    end

    it "does the same on the status form" do
      get :new_sepa_status, params: {accounting_entry: {subject_id: person.id}, hide_subject: 1}

      expect(person_row).to be_nil
      expect(doc.at_css("#accounting_entry_subject_id")["value"]).to eq(person.id.to_s)
    end

    # The view reads the controller's permitted attributes for the box.
    it "renders the fee reconciliation checkbox for the manage tier" do
      get :edit, params: {id: entry.id}

      expect(doc.at_css("input[type=checkbox][name='accounting_entry[excluded_from_fee_reconciliation]']"))
        .to be_present
    end
  end
end
