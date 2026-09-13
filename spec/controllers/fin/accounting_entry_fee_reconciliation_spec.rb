# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# "Diese Buchung nimmt nicht an der Abstimmung der TN-Beiträge teil" is a key
# inside the jsonb column additional_info, reached through a jsonb_accessor.
# Two things have to line up for the checkbox on the entry page to work: the
# view has to see that the key is editable (WsjrdpFormHelper#permitted_attr?,
# which reads both the flat and the nested spelling), and the form's flat
# field name has to be permitted, so the accessor's writer runs -- it casts to
# boolean and drops the key rather than storing "0".
describe Fin::AccountingEntriesController, type: :controller do
  render_views

  let(:manager) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }
  let(:person) { people(:yp_a_1) }

  let!(:entry) do
    AccountingEntry.create!(subject: person, author: manager,
      amount_cents: 10_000, amount_currency: "EUR",
      description: "Beitragsrate", value_date: Date.new(2026, 3, 1),
      booking_date: Date.new(2026, 3, 1))
  end

  before do
    sign_in(manager)
    # The manage tier has to be picked for the session (doc/roles.md).
    session[:max_finance_permission] = "finance_manage"
  end

  # What the read-only row says after the flag's label.
  def reconciliation_value
    Nokogiri::HTML(response.body).text.squish[/Abstimmung ausgenommen\s*(ja|nein)/, 1]
  end

  def checkbox
    Nokogiri::HTML(response.body)
      .at_css("input[type=checkbox][name='accounting_entry[excluded_from_fee_reconciliation]']")
  end

  it "offers the checkbox to the manage tier" do
    get :show, params: {id: entry.id}

    expect(checkbox).to be_present
  end

  it "leaves it out below the manage tier" do
    session[:max_finance_permission] = "finance"
    get :show, params: {id: entry.id}

    expect(checkbox).to be_nil
  end

  it "stores a checked box as the boolean true" do
    put :update, params: {id: entry.id, accounting_entry: {excluded_from_fee_reconciliation: "1"}}

    expect(entry.reload.additional_info).to eq("excluded_from_fee_reconciliation" => true)
    expect(entry).to be_excluded_from_fee_reconciliation
    expect(AccountingEntry.excluded_from_fee_reconciliation).to include(entry)
  end

  # An unchecked box posts "0". The key is dropped rather than stored as a
  # string, which "0" would be -- and a string is truthy to the reader.
  it "drops the key again when the box is unchecked" do
    entry.update!(excluded_from_fee_reconciliation: true)

    put :update, params: {id: entry.id, accounting_entry: {excluded_from_fee_reconciliation: "0"}}

    expect(entry.reload.additional_info).to eq({})
    expect(entry).not_to be_excluded_from_fee_reconciliation
    expect(AccountingEntry.fee_reconciliation_relevant).to include(entry)
  end

  # A boolean jsonb key answers true or false, never nil -- otherwise the
  # read-only row renders empty instead of "nein" (WsjrdpJsonbHelper).
  describe "the boolean reader" do
    it "reads an absent key as false" do
      expect(entry.additional_info).to eq({})
      expect(entry.excluded_from_fee_reconciliation).to be(false)
      expect(entry).not_to be_excluded_from_fee_reconciliation
    end

    it "reads a set key as true" do
      entry.update!(excluded_from_fee_reconciliation: true)

      expect(entry.reload.excluded_from_fee_reconciliation).to be(true)
    end

    # Whatever wrote it, "0" is false -- a bare double negation would call the
    # string true.
    it "reads a string the store may carry as the boolean it means" do
      entry.update_column(:additional_info, {"excluded_from_fee_reconciliation" => "0"})

      expect(entry.reload.excluded_from_fee_reconciliation).to be(false)

      entry.update_column(:additional_info, {"excluded_from_fee_reconciliation" => "1"})

      expect(entry.reload.excluded_from_fee_reconciliation).to be(true)
    end

    # Below the manage tier the row is read-only, and it has to say something.
    it "shows as ja or nein in the read-only row" do
      session[:max_finance_permission] = "finance"
      get :show, params: {id: entry.id}

      expect(reconciliation_value).to eq("nein")

      entry.update!(excluded_from_fee_reconciliation: true)
      get :show, params: {id: entry.id}

      expect(reconciliation_value).to eq("ja")
    end
  end

  # A status change books no money and never takes part in the reconciliation,
  # and it can only be a change: the status the person already holds is not on
  # offer. Both hold however the form was reached, so neither has to be
  # carried in the URL or a hidden field.
  describe "the status-change booking" do
    def statuses_on_offer
      Nokogiri::HTML(response.body)
        .css("select[name='accounting_entry[new_sepa_status]'] option")
        .pluck("value")
    end

    before { person.update!(sepa_status: "ok") }

    it "leaves the person's current status out of the select" do
      get :new_sepa_status, params: {accounting_entry: {subject_id: person.id}}

      expect(statuses_on_offer).to match_array(Settings.sepa_status.to_h.keys.map(&:to_s) - ["ok"])
      expect(statuses_on_offer).not_to include("ok")
    end

    it "follows the person: another status, another option left out" do
      person.update!(sepa_status: "in_review")
      get :new_sepa_status, params: {accounting_entry: {subject_id: person.id}}

      expect(statuses_on_offer).to include("ok")
      expect(statuses_on_offer).not_to include("in_review")
    end

    it "books nothing and stays out of the reconciliation" do
      expect do
        post :new_sepa_status, params: {accounting_entry: {subject_id: person.id,
                                                           new_sepa_status: "in_review"}}
      end.to change { AccountingEntry.count }.by(1)

      booking = AccountingEntry.order(:id).last
      expect(booking.amount_cents).to eq(0)
      expect(booking).to be_excluded_from_fee_reconciliation
      expect(person.reload.sepa_status).to eq("in_review")
    end

    # Even a request that asks for the opposite gets a booking out of the
    # reconciliation: it is the controller's call, not the form's.
    it "keeps the flag against anything the request sends" do
      post :new_sepa_status, params: {accounting_entry: {subject_id: person.id,
                                                         new_sepa_status: "missing",
                                                         amount_cents: 5000,
                                                         excluded_from_fee_reconciliation: "0"}}

      booking = AccountingEntry.order(:id).last
      expect(booking.amount_cents).to eq(0)
      expect(booking).to be_excluded_from_fee_reconciliation
    end
  end

  # Both forms can be opened bare, with nothing in the URL: no
  # accounting_entry key to require, and the person asked for in the form
  # itself. Reached from a person's fee page the subject comes along and the
  # picker gives way to the name.
  describe "opened without parameters" do
    def person_picker
      Nokogiri::HTML(response.body).at_css("[data-provide=entity][data-id-field=accounting_entry_subject_id]")
    end

    it "asks for the person on the booking form" do
      get :new

      expect(response).to be_successful
      expect(person_picker).to be_present
    end

    it "asks for the person on the status form, and offers every status" do
      get :new_sepa_status

      expect(response).to be_successful
      expect(person_picker).to be_present
      expect(Nokogiri::HTML(response.body)
        .css("select[name='accounting_entry[new_sepa_status]'] option").pluck("value"))
        .to match_array(Settings.sepa_status.to_h.keys.map(&:to_s))
    end

    it "shows the name instead of the picker once the subject is known" do
      get :new, params: {accounting_entry: {subject_id: person.id}}

      expect(person_picker).to be_nil
      expect(response.body).to include(person.to_s)
    end

    it "creates a booking for the person picked in the bare form" do
      expect do
        post :create, params: {accounting_entry: {subject_id: person.id, amount_eur: "12.34",
                                                  description: "Testbuchung"}}
      end.to change { AccountingEntry.count }.by(1)

      booking = AccountingEntry.order(:id).last
      expect(booking.subject).to eq(person)
      expect(booking.amount_cents).to eq(1234)
    end
  end

  # Where a saved form leads, and who the page frames it as. Inside the fee
  # page's frame nothing navigates; on its own the form is the page.
  describe "standing on its own" do
    def sheet_tabs
      Nokogiri::HTML(response.body).css(".sheet .nav a, .nav-tabs a").map { |a| a.text.strip }
    end

    it "sits under Beiträge, not under a person" do
      get :new

      expect(response.body).to include(I18n.t("fin.nav.fees"))
      expect(sheet_tabs).to include(I18n.t("fin.tabs.overview"), I18n.t("fin.tabs.plans"))
    end

    it "leads to the booking it just created" do
      post :create, params: {accounting_entry: {subject_id: person.id, amount_eur: "7.77",
                                                description: "Testbuchung"}}

      expect(response).to redirect_to(AccountingEntry.order(:id).last)
    end

    # The list shares its journal partial with a person's fee page, where the
    # entry is known -- it must not ask about one it does not have.
    it "lists the bookings without an entry to ask about" do
      get :index

      expect(response).to be_successful
      expect(response.body).to include("Buchungen")
    end

    # Inside the frame the fee page reloads around it, as before.
    it "reloads the page around the frame instead" do
      request.headers["Turbo-Frame"] = "accounting_extra_entry"
      post :create, params: {accounting_entry: {subject_id: person.id, amount_eur: "7.77",
                                                description: "Testbuchung"}}

      expect(response).to be_successful
      expect(response.body).to include("location_reload")
    end
  end

  # Submitted bare, the status form has to say what is missing instead of
  # falling over.
  describe "a status change with nothing filled in" do
    before { person.update!(sepa_status: "ok") }

    it "asks for the person back on the form" do
      post :new_sepa_status, params: {accounting_entry: {new_sepa_status: "in_review"}}

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to include("muss ausgewählt werden")
      expect(person.reload.sepa_status).to eq("ok")
    end

    it "asks for the status the same way" do
      expect do
        post :new_sepa_status, params: {accounting_entry: {subject_id: person.id,
                                                           new_sepa_status: ""}}
      end.not_to change(AccountingEntry, :count)

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to include("muss ausgewählt werden")
    end
  end

  # A page that already names the person says so, and the form leaves the
  # person out -- the id still travels, hidden.
  describe "hide_subject" do
    def person_row
      Nokogiri::HTML(response.body).text.squish[/Person\s*#{Regexp.escape(person.to_s)}/]
    end

    it "leaves the person out of the form when the page asks for it" do
      get :new, params: {accounting_entry: {subject_id: person.id}, hide_subject: 1}

      expect(person_row).to be_nil
      expect(Nokogiri::HTML(response.body).at_css("#accounting_entry_subject_id")["value"])
        .to eq(person.id.to_s)
      expect(Nokogiri::HTML(response.body).at_css("input[name=hide_subject]")).to be_present
    end

    it "shows the person without the option" do
      get :new, params: {accounting_entry: {subject_id: person.id}}

      expect(person_row).to be_present
    end

    it "does the same on the status form" do
      get :new_sepa_status, params: {accounting_entry: {subject_id: person.id}, hide_subject: 1}

      expect(person_row).to be_nil
      expect(Nokogiri::HTML(response.body).at_css("#accounting_entry_subject_id")["value"])
        .to eq(person.id.to_s)
    end
  end

  # The predicate the view asks, in both spellings a controller may use.
  describe "WsjrdpFormHelper#permitted_attr?" do
    let(:view) do
      Class.new do
        include WsjrdpFormHelper
        attr_writer :permitted_attrs

        attr_reader :permitted_attrs
      end.new
    end

    it "counts a jsonb key as permitted whether it is listed flat or nested" do
      view.permitted_attrs = [:comment, :excluded_from_fee_reconciliation]
      expect(view.permitted_attr?(:excluded_from_fee_reconciliation)).to be(true)

      view.permitted_attrs = [:comment, {additional_info: [:excluded_from_fee_reconciliation]}]
      expect(view.permitted_attr?(:excluded_from_fee_reconciliation)).to be(true)
      expect(view.permitted_attr?(:comment)).to be(true)
      expect(view.permitted_attr?(:amount_eur)).to be(false)
    end
  end
end
