# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The person-linking actions of a Moss booking (SubjectLinking +
# Fin::MossBookingsController): who may run them, what they write, and that a
# Turbo request gets back exactly the booking's linking blocks
# (fin/moss_bookings/_subject_links, every occurrence on the page) plus a reload
# of the transaction's already loaded detail frames -- instead of a page refresh.
# All names, numbers and amounts are invented.
describe Fin::MossBookingsController do
  before_all(setup_fixtures: true) {}

  let_it_be(:finance, refind: true) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let_it_be(:target) { people(:cmt_leader) }

  let_it_be(:wallet) do
    WsjrdpFinAccount.create!(short_name: "Moss-Wallet", account_identification: "MOSS-WALLET-TEST",
      transaction_type: "MossBalanceMovement", opening_balance_cents: 100_000,
      opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
  end

  # A reimbursement whose text names the target ("CMT <id>"), so the wallet
  # offers the target as a link candidate.
  let_it_be(:booking, refind: true) do
    uuid = SecureRandom.uuid
    transaction = MossTransaction.create!(type: "MossReimbursement", moss_transaction_uuid: uuid,
      fin_account: wallet, signed_total_base_amount: -60, currency: "EUR",
      booking_date: Date.new(2026, 6, 1), transaction_name: "Fahrtkosten Vortreffen")
    expense = MossExpense.create!(moss_transaction: transaction, moss_expense_uuid: uuid,
      type: "MossReimbursementExpense", expense_number: 1, signed_expense_base_amount: -60)
    MossBooking.create!(moss_transaction: transaction, moss_expense: expense, sub_row_number: 1,
      signed_base_amount: -60, booking_posting_text: "Erstattung CMT #{target.id}")
  end

  let(:block_selector) { "[data-subject-links='moss_booking_#{booking.id}']" }

  def link_params(subject_type: "Person", subject_id: target.id)
    {moss_booking_id: booking.id, subject_id: subject_id, subject_type: subject_type}
  end

  # The signed-in user keeps every right except `action` on `subject` -- cases
  # the fixtures cannot express (the finance roles also hold
  # layer_and_below_full and :create on AccountingEntry).
  def deny(action, subject)
    allow(controller).to receive(:current_ability).and_wrap_original do |original|
      original.call.tap do |ability|
        allow(ability).to receive(:can?).and_call_original
        allow(ability).to receive(:can?).with(action, subject).and_return(false)
      end
    end
  end

  def deny_update_on(person) = deny(:update, person)

  def entry_for(person, amount_cents: -6000, booking_date: Date.new(2026, 6, 1), **links)
    AccountingEntry.create!(subject: person, author: finance, amount_cents: amount_cents,
      description: "Beitrag", value_date: booking_date, booking_date: booking_date, **links)
  end

  def streams = Nokogiri::HTML(response.body).css("turbo-stream")

  # The block replacement (the first stream).
  def stream = streams.first

  def post_turbo(action, params = link_params) = post(action, params: params, format: :turbo_stream)

  context "as finance (write tier)" do
    before { sign_in(finance) }

    describe "POST link_subject" do
      it "links the person, replaces every linking block and reloads the loaded detail frames" do
        post_turbo :link_subject

        reload = streams.find { |s| s["action"] == "reload_frames" }
        aggregate_failures do
          expect(response.media_type).to eq "text/vnd.turbo-stream.html"
          expect(stream["action"]).to eq "replace"
          expect(stream["targets"]).to eq block_selector
          expect(reload["targets"])
            .to eq "turbo-frame[data-record='moss_transaction_#{booking.moss_transaction_id}'][complete], " \
              "turbo-frame[data-record='moss_booking_#{booking.id}'][complete]"
          expect(booking.reload.contribution_subject).to eq target
          expect(booking.contribution_subject_link_meta).to include(
            "author_id" => finance.id, "automatic_manual" => "manual", "score" => nil, "classification_string" => nil
          )
        end
      end

      it "goes back to the page it came from without Turbo" do
        request.env["HTTP_REFERER"] = "http://test.host/fin/moss/bookings?p=2"
        post :link_subject, params: link_params

        expect(response).to redirect_to("http://test.host/fin/moss/bookings?p=2")
        expect(booking.reload.contribution_subject).to eq target
      end

      it "refuses without :update on the person and links nothing" do
        deny_update_on(target)

        expect { post_turbo :link_subject }.to raise_error(CanCan::AccessDenied)
        expect(booking.reload.contribution_subject).to be_nil
      end

      it "rejects any subject type but Person" do
        expect { post_turbo :link_subject, link_params(subject_type: "Group") }
          .to raise_error(ActionController::BadRequest)
        expect(booking.reload.contribution_subject).to be_nil
      end
    end

    describe "POST disallow_link_subject" do
      it "puts the person on the booking's deny list and replaces the block" do
        post_turbo :disallow_link_subject

        aggregate_failures do
          expect(stream["targets"]).to eq block_selector
          expect(booking.reload.denylist_subject_candidates).to eq [[target.id, "Person"]]
          expect(booking.contribution_subject).to be_nil
        end
      end

      it "refuses without :update on the person and leaves the deny list alone" do
        deny_update_on(target)

        expect { post_turbo :disallow_link_subject }.to raise_error(CanCan::AccessDenied)
        expect(booking.reload.denylist_subject_candidates).to be_blank
      end
    end

    describe "the re-rendered linking block" do
      render_views

      it "shows the person, who linked it and when, and the next step" do
        post_turbo :link_subject

        expect(stream.text).to include("verknüpft am #{Time.zone.today.strftime("%d.%m.%Y")}")
          .and include("(manuell)").and include("Person:").and include("Erzeuge Buchung")
      end

      it "names the matching unlinked Beitragsbuchung that blocks a new one" do
        existing = entry_for(target, booking_date: Date.new(2026, 4, 1))
        post_turbo :link_subject_and_create_accounting_entry

        expect(stream.text).to include("1 passende Beitragsbuchung vorhanden").and include("##{existing.id}")
      end
    end
  end

  # The reading page leads to the edit page; the list's row lazy-loads the same
  # detail in its frame.
  describe "the reading page, the row detail and the edit page" do
    before { sign_in(finance) }

    it "answers a row's frame with the embedded detail" do
      request.headers["Turbo-Frame"] = "bkframe-mbk-#{booking.id}"
      get :show, params: {id: booking.id, expandable_table_level: 1}

      expect(assigns(:ctx)).to be_embedded
    end

    describe "the row's detail" do
      render_views

      def forms = Nokogiri::HTML(response.body).css("turbo-frame#bkframe-mbk-#{booking.id} form")

      # The row's detail carries the kit's inline edit for whoever may write.
      it "gives the row's detail the inline edit form" do
        request.headers["Turbo-Frame"] = "bkframe-mbk-#{booking.id}"
        get :show, params: {id: booking.id, expandable_table_level: 1}

        form = forms.find { |f| f["action"] == moss_booking_path(booking) }
        expect(form.at_css("textarea[name='moss_booking[comment]']")).to be_present
      end

      it "leaves the inline edit out without :update on the booking" do
        deny(:update, booking)
        request.headers["Turbo-Frame"] = "bkframe-mbk-#{booking.id}"
        get :show, params: {id: booking.id, expandable_table_level: 1}

        expect(forms).to be_empty
      end
    end

    it "brings a save from the row back to the row's detail" do
      request.headers["Turbo-Frame"] = "bkframe-mbk-#{booking.id}"
      patch :update, params: {id: booking.id, moss_booking: {comment: "Geprüft"}}

      expect(response).to redirect_to(moss_booking_path(booking))
      expect(booking.reload.comment).to eq "Geprüft"
    end

    it "renders the edit page" do
      get :edit, params: {id: booking.id}
      expect(response).to be_successful
    end

    it "saves and returns to the reading page" do
      patch :update, params: {id: booking.id, moss_booking: {comment: "Geprüft"}}

      expect(response).to redirect_to(moss_booking_path(booking))
      expect(booking.reload.comment).to eq "Geprüft"
    end

    it "stays on the edit page with 'Speichern und weiter bearbeiten'" do
      patch :update, params: {id: booking.id, stay: "1", moss_booking: {comment: "Geprüft"}}

      expect(response).to redirect_to(edit_moss_booking_path(booking))
    end

    it "returns to the page the reader came from" do
      patch :update, params: {id: booking.id, return_url: "/fin/moss/bookings?p=2", moss_booking: {comment: "x"}}

      expect(response).to redirect_to("/fin/moss/bookings?p=2")
    end

    it "refuses the edit page without :update on the booking" do
      deny(:update, booking)

      expect { get :edit, params: {id: booking.id} }.to raise_error(CanCan::AccessDenied)
    end
  end

  describe "POST link_subject_and_create_accounting_entry" do
    before { sign_in(finance) }

    it "links the person and creates their linked Beitragsbuchung, both as a manual link" do
      expect { post_turbo :link_subject_and_create_accounting_entry }.to change(AccountingEntry, :count).by(1)

      entry = AccountingEntry.last
      aggregate_failures do
        expect(response).to be_successful
        expect(booking.reload.contribution_subject).to eq target
        expect(entry).to have_attributes(subject: target, amount_cents: -6000,
          moss_booking_id: booking.id, booking_date: Date.new(2026, 6, 1), author: finance)
        expect(stream["targets"]).to eq block_selector
        expect(booking.contribution_subject_link_meta)
          .to include("author_id" => finance.id, "automatic_manual" => "manual")
        expect(entry.moss_booking_link_meta).to include(
          "author_id" => finance.id, "automatic_manual" => "manual", "score" => nil, "classification_string" => nil
        )
        expect(entry.moss_booking_link_meta["created_at"]).to be_present
      end
    end

    it "takes the booking's Buchungstext and comment, not the transaction's text" do
      booking.update!(comment: "Rückzahlung geprüft")
      post_turbo :link_subject_and_create_accounting_entry

      expect(AccountingEntry.last).to have_attributes(
        description: "Erstattung CMT #{target.id}", comment: "Rückzahlung geprüft"
      )
    end

    it "refuses once the booking has a Beitragsbuchung instead of creating a second one" do
      entry = entry_for(target)
      booking.update!(contribution_subject: target, accounting_entry_id: entry.id)

      expect { post_turbo :link_subject_and_create_accounting_entry }.not_to change(AccountingEntry, :count)
      expect(response).to have_http_status(422)
      expect(stream["targets"]).to eq block_selector
    end

    it "refuses while the person has a matching unlinked Beitragsbuchung" do
      entry_for(target, booking_date: Date.new(2026, 4, 1))

      expect { post_turbo :link_subject_and_create_accounting_entry }.not_to change(AccountingEntry, :count)
      expect(response).to have_http_status(422)
      expect(booking.reload.contribution_subject).to be_nil
    end

    it "creates despite an unlinked entry of the amount older than 3 months" do
      entry_for(target, booking_date: Date.new(2026, 2, 1))

      expect { post_turbo :link_subject_and_create_accounting_entry }.to change(AccountingEntry, :count).by(1)
    end

    it "redirects with an alert without Turbo when refused" do
      entry_for(target)
      post :link_subject_and_create_accounting_entry, params: link_params

      expect(response).to redirect_to(moss_booking_path(booking))
      expect(flash[:alert]).to include("Keine Beitragsbuchung angelegt")
    end

    it "writes nothing when creating the Beitragsbuchung fails" do
      allow(AccountingEntry).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AccountingEntry.new))

      expect { post_turbo :link_subject_and_create_accounting_entry }.to raise_error(ActiveRecord::RecordInvalid)
      expect(booking.reload.contribution_subject).to be_nil
    end

    it "refuses without :update on the person" do
      deny_update_on(target)

      expect { post_turbo :link_subject_and_create_accounting_entry }.to raise_error(CanCan::AccessDenied)
      expect(AccountingEntry.where(moss_booking_id: booking.id)).to be_empty
    end

    it "refuses without :create on AccountingEntry" do
      deny(:create, AccountingEntry)

      expect { post_turbo :link_subject_and_create_accounting_entry }.to raise_error(CanCan::AccessDenied)
      expect(booking.reload.contribution_subject).to be_nil
    end
  end

  describe "POST create_accounting_entry" do
    before do
      sign_in(finance)
      booking.update!(contribution_subject: target)
    end

    def create_params = {moss_booking_id: booking.id}

    it "creates the Beitragsbuchung of the linked person, with the link's provenance" do
      expect { post_turbo :create_accounting_entry, create_params }.to change(AccountingEntry, :count).by(1)
      expect(AccountingEntry.last.moss_booking_link_meta)
        .to include("author_id" => finance.id, "automatic_manual" => "manual")
    end

    it "takes the booking's Buchungstext and comment, not the transaction's text" do
      booking.update!(comment: "Rückzahlung geprüft")
      post_turbo :create_accounting_entry, create_params

      expect(AccountingEntry.last).to have_attributes(
        description: "Erstattung CMT #{target.id}", comment: "Rückzahlung geprüft"
      )
    end

    it "falls back to the booking's composed description when its Buchungstext is empty" do
      booking.update!(booking_posting_text: "")
      post_turbo :create_accounting_entry, create_params

      expect(AccountingEntry.last.description).to eq("Fahrtkosten Vortreffen")
    end

    it "refuses without :create on AccountingEntry" do
      deny(:create, AccountingEntry)

      expect { post_turbo :create_accounting_entry, create_params }.to raise_error(CanCan::AccessDenied)
    end
  end

  describe "POST link_accounting_entry" do
    before do
      sign_in(finance)
      booking.update!(contribution_subject: target)
    end

    it "links the existing Beitragsbuchung with the link's provenance" do
      existing = entry_for(target)
      post_turbo :link_accounting_entry, {moss_booking_id: booking.id, accounting_entry_id: existing.id}

      existing.reload
      expect(existing.moss_booking_id).to eq booking.id
      expect(existing.moss_booking_link_meta).to include("author_id" => finance.id, "automatic_manual" => "manual")
    end
  end

  context "as finance reader (read tier)" do
    let_it_be(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }

    before { sign_in(reader) }

    it "may not link" do
      expect { post_turbo :link_subject }.to raise_error(CanCan::AccessDenied)
      expect(booking.reload.contribution_subject).to be_nil
    end

    it "may not create a Beitragsbuchung in one step" do
      expect { post_turbo :link_subject_and_create_accounting_entry }.to raise_error(CanCan::AccessDenied)
      expect(booking.reload.contribution_subject).to be_nil
    end

    it "may not refuse a candidate" do
      expect { post_turbo :disallow_link_subject }.to raise_error(CanCan::AccessDenied)
      expect(booking.reload.denylist_subject_candidates).to be_blank
    end
  end
end
