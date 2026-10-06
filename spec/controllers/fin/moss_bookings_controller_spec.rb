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
  render_views

  let(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let(:target) { people(:cmt_leader) }

  let!(:wallet) do
    WsjrdpFinAccount.create!(short_name: "Moss-Wallet", account_identification: "MOSS-WALLET-TEST",
      transaction_type: "MossBalanceMovement", opening_balance_cents: 100_000,
      opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
  end

  # A reimbursement whose text names the target ("CMT <id>"), so the wallet
  # offers the target as a link candidate.
  let!(:booking) do
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

  context "as finance (write tier)" do
    before { sign_in(finance) }

    describe "POST link_subject" do
      it "links the person and replaces every occurrence of the booking's linking block" do
        post :link_subject, params: link_params, format: :turbo_stream

        expect(response).to be_successful
        expect(response.media_type).to eq "text/vnd.turbo-stream.html"
        expect(stream["action"]).to eq "replace"
        expect(stream["targets"]).to eq block_selector
        expect(stream.at_css(block_selector)).to be_present
        expect(booking.reload.contribution_subject).to eq target
      end

      it "reloads the already loaded detail frames of the booking's transaction" do
        post :link_subject, params: link_params, format: :turbo_stream

        reload = streams.find { |s| s["action"] == "reload_frames" }
        expect(reload["targets"])
          .to eq "turbo-frame[data-record='moss_transaction_#{booking.moss_transaction_id}'][complete]"
      end

      it "records who linked the person, and when, and shows it next to the person" do
        post :link_subject, params: link_params, format: :turbo_stream

        expect(booking.reload.contribution_subject_link_meta).to include(
          "author_id" => finance.id, "automatic_manual" => "manual", "score" => nil, "classification_string" => nil
        )
        expect(stream.text).to include("verknüpft am #{Time.zone.today.strftime("%d.%m.%Y")}")
          .and include("(manuell)")
      end

      it "re-renders the block in its new state: the person and the next step" do
        post :link_subject, params: link_params, format: :turbo_stream

        expect(stream.text).to include("Person:").and include("Erzeuge Buchung")
        expect(stream.text).not_to include("Keine Verknüpfung mit")
      end

      it "redirects to the wallet without Turbo" do
        post :link_subject, params: link_params

        expect(response).to redirect_to(wallet)
        expect(booking.reload.contribution_subject).to eq target
      end

      it "refuses without :update on the person and links nothing" do
        deny_update_on(target)

        expect { post :link_subject, params: link_params, format: :turbo_stream }
          .to raise_error(CanCan::AccessDenied)
        expect(booking.reload.contribution_subject).to be_nil
      end

      it "rejects any subject type but Person" do
        expect { post :link_subject, params: link_params(subject_type: "Group"), format: :turbo_stream }
          .to raise_error(ActionController::BadRequest)
        expect(booking.reload.contribution_subject).to be_nil
      end
    end

    describe "POST disallow_link_subject" do
      it "puts the person on the booking's deny list and drops the offer from the block" do
        post :disallow_link_subject, params: link_params, format: :turbo_stream

        expect(response).to be_successful
        expect(stream["targets"]).to eq block_selector
        expect(booking.reload.denylist_subject_candidates).to eq [[target.id, "Person"]]
        expect(booking.contribution_subject).to be_nil
        expect(stream.text).not_to include("Verknüpfe mit")
      end

      it "refuses without :update on the person and leaves the deny list alone" do
        deny_update_on(target)

        expect { post :disallow_link_subject, params: link_params, format: :turbo_stream }
          .to raise_error(CanCan::AccessDenied)
        expect(booking.reload.denylist_subject_candidates).to be_blank
      end
    end
  end

  describe "GET show" do
    before { sign_in(finance) }

    def page = Nokogiri::HTML(response.body)

    def row(label)
      page.css("#main .row").find { |r| r.element_children.first&.text&.strip == label }
    end

    it "heads the page with the muted id and the booking's Buchungstext" do
      get :show, params: {id: booking.id}

      h1 = page.at_css("#main h1")
      expect(h1.at_css("span.text-muted.fw-light").text).to eq "Moss Buchung ##{booking.id}"
      expect(h1.text).to include("Erstattung CMT #{target.id}")
    end

    it "leaves the title out when the booking has no Buchungstext" do
      booking.update!(booking_posting_text: "")
      get :show, params: {id: booking.id}

      expect(page.at_css("#main h1").css("span").size).to eq 1
    end

    it "shows the amount with two decimals" do
      booking.update!(signed_base_amount: -60)
      get :show, params: {id: booking.id}

      expect(row("Betrag").text).to include("-60,00")
      expect(row("Betrag").text).not_to include(",—")
    end

    it "links the account twice: here and in a new tab" do
      get :show, params: {id: booking.id}

      expect(row("Konto/Wallet").text).not_to include("aus der Transaktion")
      hrefs = row("Konto/Wallet").css("a").map { |a| [a["href"], a["target"]] }
      expect(hrefs).to eq [["/fin/acc/#{wallet.id}", nil], ["/fin/acc/#{wallet.id}", "_blank"]]
    end

    it "shows the kind on its own line, without a source hint" do
      get :show, params: {id: booking.id}

      expect(row("Art").text.squish).to include("Erstattung")
      expect(row("Art").text).not_to include("aus der Transaktion")
    end

    it "shows only the booking, submission and approval dates of the transaction" do
      booking.moss_transaction.update!(payment_date: Date.new(2026, 5, 30), due_date: Date.new(2026, 6, 15),
        submitted_date: Date.new(2026, 5, 20), approval_date: Date.new(2026, 5, 25))
      get :show, params: {id: booking.id}

      labels = page.css("#main fieldset .row").map { |r| r.element_children.first&.text&.strip }
      expect(labels).to include("Buchungsdatum", "Eingereicht am", "Freigegeben am")
      expect(labels).not_to include("Zahlungsdatum", "Fälligkeitsdatum", "Verwendungszweck")
    end

    it "marks every date of the transaction as coming from it" do
      get :show, params: {id: booking.id}

      expect(row("Buchungsdatum").text.squish).to include("01.06.2026").and include("aus der Transaktion")
    end

    it "puts the amount first" do
      get :show, params: {id: booking.id}

      labels = page.css("#main fieldset .row").map { |r| r.element_children.first&.text&.strip }
      expect(labels.first).to eq "Betrag"
    end

    it "lists the booking's own Buchungstext even where it repeats the text above" do
      booking.moss_transaction.update!(transaction_name: booking.booking_posting_text)
      get :show, params: {id: booking.id}

      expect(row("Buchungstext").text.squish).to include("Buchung: Erstattung CMT #{target.id}")
    end

    it "links the payment in Moss twice, on a line of its own" do
      booking.moss_transaction.update!(moss_reimbursement_uuid: SecureRandom.uuid)
      get :show, params: {id: booking.id}

      moss_line = row("Transaktion").css("div").find { |d| d.text.strip == "in Moss öffnen" }
      expect(moss_line.css("a").pluck("target")).to eq [nil, "_blank"]
    end

    it "links the transaction as \"#<id>\" twice, then its text, without a repeated amount" do
      booking.moss_transaction.update!(transaction_posting_text: "Fahrt Vortreffen")
      get :show, params: {id: booking.id}

      line = row("Transaktion").css("div").first
      path = "/fin/moss/transactions/#{booking.moss_transaction_id}"
      expect(line.css("a").map { |a| [a.text.strip, a["href"], a["target"]] })
        .to eq [["##{booking.moss_transaction_id}", path, nil], ["", path, "_blank"]]
      expect(line.text.squish).to eq "##{booking.moss_transaction_id} Fahrt Vortreffen"
    end

    it "adds the transaction's amount where it differs from the booking's" do
      booking.moss_transaction.update!(signed_total_base_amount: -150)
      get :show, params: {id: booking.id}

      expect(row("Transaktion").css("div").first.text.squish).to include("(-150,00")
    end

    it "shows the transaction as text without :show on it" do
      deny(:show, booking.moss_transaction)
      get :show, params: {id: booking.id}

      expect(row("Transaktion").css("a").pluck("href"))
        .not_to include("/fin/moss/transactions/#{booking.moss_transaction_id}")
      expect(row("Transaktion").text).to include("##{booking.moss_transaction_id}")
    end
  end

  describe "POST link_subject_and_create_accounting_entry" do
    before { sign_in(finance) }

    def create_params = link_params

    it "links the person and creates their linked Beitragsbuchung" do
      expect { post :link_subject_and_create_accounting_entry, params: create_params, format: :turbo_stream }
        .to change(AccountingEntry, :count).by(1)

      expect(response).to be_successful
      expect(booking.reload.contribution_subject).to eq target
      entry = AccountingEntry.last
      expect(entry).to have_attributes(subject: target, amount_cents: -6000, moss_booking_id: booking.id,
        booking_date: Date.new(2026, 6, 1), author: finance)
      expect(stream["targets"]).to eq block_selector
      expect(stream.text).to include("Verknüpfte Buchung")
    end

    it "takes the booking's Buchungstext and comment, not the transaction's text" do
      booking.update!(comment: "Rückzahlung geprüft")
      post :link_subject_and_create_accounting_entry, params: create_params, format: :turbo_stream

      expect(AccountingEntry.last).to have_attributes(
        description: "Erstattung CMT #{target.id}", comment: "Rückzahlung geprüft"
      )
    end

    it "records who linked it, and when, as a manual link -- person and Beitragsbuchung" do
      post :link_subject_and_create_accounting_entry, params: create_params, format: :turbo_stream

      expect(booking.reload.contribution_subject_link_meta)
        .to include("author_id" => finance.id, "automatic_manual" => "manual")

      expect(AccountingEntry.last.moss_booking_link_meta).to include(
        "author_id" => finance.id, "automatic_manual" => "manual", "score" => nil, "classification_string" => nil
      )
      expect(AccountingEntry.last.moss_booking_link_meta["created_at"]).to be_present
    end

    it "refuses a second time instead of creating a second Beitragsbuchung" do
      post :link_subject_and_create_accounting_entry, params: create_params, format: :turbo_stream

      expect { post :link_subject_and_create_accounting_entry, params: create_params, format: :turbo_stream }
        .not_to change(AccountingEntry, :count)
      expect(response).to have_http_status(422)
      expect(stream["targets"]).to eq block_selector
    end

    it "refuses while the person has a matching unlinked Beitragsbuchung, and names it" do
      existing = entry_for(target, booking_date: Date.new(2026, 4, 1))

      expect { post :link_subject_and_create_accounting_entry, params: create_params, format: :turbo_stream }
        .not_to change(AccountingEntry, :count)
      expect(response).to have_http_status(422)
      expect(booking.reload.contribution_subject).to be_nil
      expect(stream.text).to include("1 passende Beitragsbuchung vorhanden").and include("##{existing.id}")
    end

    it "creates despite an unlinked entry of the amount older than 3 months" do
      entry_for(target, booking_date: Date.new(2026, 2, 1))

      expect { post :link_subject_and_create_accounting_entry, params: create_params, format: :turbo_stream }
        .to change(AccountingEntry, :count).by(1)
    end

    it "redirects with an alert without Turbo when refused" do
      entry_for(target)
      post :link_subject_and_create_accounting_entry, params: create_params

      expect(response).to redirect_to(wallet)
      expect(flash[:alert]).to include("Keine Beitragsbuchung angelegt")
    end

    it "writes nothing when creating the Beitragsbuchung fails" do
      allow(AccountingEntry).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AccountingEntry.new))

      expect { post :link_subject_and_create_accounting_entry, params: create_params, format: :turbo_stream }
        .to raise_error(ActiveRecord::RecordInvalid)
      expect(booking.reload.contribution_subject).to be_nil
    end

    it "refuses without :update on the person" do
      deny_update_on(target)

      expect { post :link_subject_and_create_accounting_entry, params: create_params, format: :turbo_stream }
        .to raise_error(CanCan::AccessDenied)
      expect(AccountingEntry.where(moss_booking_id: booking.id)).to be_empty
    end

    it "refuses without :create on AccountingEntry" do
      deny(:create, AccountingEntry)

      expect { post :link_subject_and_create_accounting_entry, params: create_params, format: :turbo_stream }
        .to raise_error(CanCan::AccessDenied)
      expect(booking.reload.contribution_subject).to be_nil
    end
  end

  describe "POST create_accounting_entry" do
    before do
      sign_in(finance)
      booking.update!(contribution_subject: target)
    end

    it "creates the Beitragsbuchung of the linked person, with the link's provenance" do
      expect { post :create_accounting_entry, params: {moss_booking_id: booking.id}, format: :turbo_stream }
        .to change(AccountingEntry, :count).by(1)
      expect(AccountingEntry.last.moss_booking_link_meta)
        .to include("author_id" => finance.id, "automatic_manual" => "manual")
    end

    it "takes the booking's Buchungstext and comment, not the transaction's text" do
      booking.update!(comment: "Rückzahlung geprüft")
      post :create_accounting_entry, params: {moss_booking_id: booking.id}, format: :turbo_stream

      expect(AccountingEntry.last).to have_attributes(
        description: "Erstattung CMT #{target.id}", comment: "Rückzahlung geprüft"
      )
    end

    it "falls back to the booking's composed description when its Buchungstext is empty" do
      booking.update!(booking_posting_text: "")
      post :create_accounting_entry, params: {moss_booking_id: booking.id}, format: :turbo_stream

      expect(AccountingEntry.last.description).to eq("Fahrtkosten Vortreffen")
    end

    it "refuses without :create on AccountingEntry" do
      deny(:create, AccountingEntry)

      expect { post :create_accounting_entry, params: {moss_booking_id: booking.id}, format: :turbo_stream }
        .to raise_error(CanCan::AccessDenied)
    end
  end

  describe "POST link_accounting_entry" do
    before do
      sign_in(finance)
      booking.update!(contribution_subject: target)
    end

    it "links the existing Beitragsbuchung with the link's provenance" do
      existing = entry_for(target)
      post :link_accounting_entry, params: {moss_booking_id: booking.id, accounting_entry_id: existing.id},
        format: :turbo_stream

      existing.reload
      expect(existing.moss_booking_id).to eq booking.id
      expect(existing.moss_booking_link_meta).to include("author_id" => finance.id, "automatic_manual" => "manual")
    end
  end

  context "as finance reader (read tier)" do
    before { sign_in(Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person) }

    it "may not link" do
      expect { post :link_subject, params: link_params, format: :turbo_stream }
        .to raise_error(CanCan::AccessDenied)
      expect(booking.reload.contribution_subject).to be_nil
    end

    it "may not create a Beitragsbuchung in one step" do
      expect { post :link_subject_and_create_accounting_entry, params: link_params, format: :turbo_stream }
        .to raise_error(CanCan::AccessDenied)
      expect(booking.reload.contribution_subject).to be_nil
    end

    it "may not refuse a candidate" do
      expect { post :disallow_link_subject, params: link_params, format: :turbo_stream }
        .to raise_error(CanCan::AccessDenied)
      expect(booking.reload.denylist_subject_candidates).to be_blank
    end
  end
end
