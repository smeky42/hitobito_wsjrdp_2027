# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The two READ-ONLY finance tiers (doc/roles.md -> "Finance tiers") on the
# /fin pages. The sections are gated on :show, which is what lets both of them
# reach the pages at all:
#
#   reader   Group::Root::FinanceReader     -- :finance_read
#   auditor  Group::Extern::FinanceAuditor -- :finance_read + :finance_audit
#
# Neither may write, and that is asserted for the auditor throughout (whatever
# the auditor may not do, the stricter reader may not either). Where the two
# differ -- the Beitragsbuchungen and the person-level fee list, which the
# audit tier sees and the read tier does not -- both are asserted side by side.
#
# The two halves of the write boundary are asserted together:
#
#   * the controller refuses the writing actions (:update for connecting and
#     unlinking, :fin_admin for the field edits and the dev-only reset),
#   * the view offers no control that would trigger one -- no checkboxes, no
#     "Auswahl verbinden", no "Verbinden", no unlink button, no connect widget.
#
# The second half is not cosmetic: a Speichern button that can only answer 403
# is what turns a permission boundary into a bug report.
describe "finance read tier (Buchhaltung / Abstimmung)" do
  let(:extern) { Group::Extern.create!(name: "Extern", parent: groups(:root)) }
  let(:auditor) { Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: extern).person }
  let(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }
  let(:accountant) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let(:fin_admin) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }

  let!(:batch) do
    DatevBookingBatch.create!(consultant_number: "1", client_number: "2",
      label: "Teststapel", period_from: Date.new(2026, 1, 1),
      period_to: Date.new(2026, 1, 31), financial_year_start: Date.new(2026, 1, 1),
      primanota_number: "01-2026/0001", import_export: "import")
  end

  let!(:booking) do
    DatevBooking.create!(batch: batch, buchungs_guid: SecureRandom.uuid,
      account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "41030", offsetting_account_kind: "INCOME",
      cost_center_number: "9500",
      base_amount: 100, transaction_amount: 100, debit_credit: "D",
      base_currency: "EUR", booking_date: Date.new(2026, 2, 1),
      posting_text: "Testbuchung Alpha")
  end

  let!(:entry) do
    AccountingEntry.create!(subject: people(:yp_a_1), author: accountant,
      amount_cents: 10_000, amount_currency: "EUR",
      description: "Teilnahmebeitrag", value_date: Date.new(2026, 2, 1),
      booking_date: Date.new(2026, 2, 1))
  end

  describe ::Fin::BookingsController, type: :controller do
    render_views

    # The forms themselves, not the page text: the detail's confirm JS names
    # both CSS classes in a string, so a plain body match would always hit.
    def forms(css) = Nokogiri::HTML(response.body).css("form#{css}")

    context "as an external auditor (read tier)" do
      before { sign_in(auditor) }

      it "renders the booking detail without unlink button or connect widget" do
        get :show, params: {id: booking.id}

        expect(response).to be_successful
        expect(response.body).to include("Testbuchung Alpha")
        expect(response.body).to include("Verknüpfungen")
        # The two write controls of the Verknüpfungen block.
        expect(forms(".bk-connect-entry-form")).to be_empty
        expect(forms(".bk-unlink-form")).to be_empty
        expect(response.body).to include("nicht verknüpft")
        # ... and the field edits, which are the manage tier's anyway.
        expect(response.body).not_to include("datev_booking[secondary_cost_center_number]")
      end

      it "refuses to connect a Beitragsbuchung" do
        expect do
          patch :update, params: {id: booking.id,
                                  datev_booking: {accounting_entry_id: entry.id}}
        end.to raise_error(CanCan::AccessDenied)
        expect(entry.reload.datev_booking_id).to be_nil
      end

      it "refuses to unlink" do
        expect do
          patch :update, params: {id: booking.id, datev_booking: {accounting_entry_id: ""}}
        end.to raise_error(CanCan::AccessDenied)
      end

      it "refuses the autocomplete that feeds the connect widget" do
        expect do
          get :query_entries, params: {id: booking.id, q: "1"}
        end.to raise_error(CanCan::AccessDenied)
      end
    end

    context "as an accountant (write tier)" do
      before { sign_in(accountant) }

      it "still renders the connect widget and connects" do
        get :show, params: {id: booking.id}
        expect(forms(".bk-connect-entry-form")).not_to be_empty

        patch :update, params: {id: booking.id, datev_booking: {accounting_entry_id: entry.id}}
        expect(entry.reload.datev_booking_id).to eq(booking.id)
      end

      # The field edits stay the manage tier's -- the same gate the detail view
      # asks before it builds the form (fin/bookings/_detail).
      it "may not edit the booking fields" do
        expect do
          patch :update, params: {id: booking.id,
                                  datev_booking: {sub_cost_center_number: "X1"}}
        end.to raise_error(CanCan::AccessDenied)
        expect(booking.reload.sub_cost_center_number).to be_nil
      end
    end

    context "as a finance admin" do
      before { sign_in(fin_admin) }

      # The sub cost center of a booking is the pair (cost_center_number,
      # sub_cost_center_number); the row it names lives under the booking's own
      # cost center (doc/fin/sub_cost_centers.md).
      it "may edit the booking fields" do
        WsjrdpSubCostCenter.create!(cost_center_number: "9500", number: "X1", name: "Teil X")

        patch :update, params: {id: booking.id,
                                datev_booking: {sub_cost_center_number: "X1"}}
        expect(booking.reload.sub_cost_center_number).to eq("X1")
      end

      # "nicht gesetzt" of the select posts the empty string; the column holds
      # NULL for a booking without a sub cost center, never "".
      it "clears the sub cost center to NULL" do
        WsjrdpSubCostCenter.create!(cost_center_number: "9500", number: "X1", name: "Teil X")
        booking.update_column(:sub_cost_center_number, "X1")

        patch :update, params: {id: booking.id,
                                datev_booking: {sub_cost_center_number: ""}}
        expect(booking.reload.sub_cost_center_number).to be_nil
      end
    end
  end

  describe ::Fin::ReconciliationController, type: :controller do
    render_views

    context "as an external auditor (read tier)" do
      before { sign_in(auditor) }

      it "renders the page as a reading view -- no connect controls, no checkboxes" do
        get :participant_fees

        expect(response).to be_successful
        expect(response.body).to include("TN-Beiträge")
        expect(response.body).not_to include("Auswahl verbinden")
        expect(response.body).not_to include("bk-connect-form")
        expect(response.body).not_to include("ae-connect-form")
        expect(response.body).not_to include("Alle Verknüpfungen zurücksetzen")
      end

      %i[connect_participant_fees connect_participant_entries].each do |action|
        it "refuses #{action}" do
          expect { post action }.to raise_error(CanCan::AccessDenied)
        end
      end

      it "refuses connect_single" do
        expect do
          post :connect_single, params: {booking_id: booking.id, entry_id: entry.id}
        end.to raise_error(CanCan::AccessDenied)
        expect(entry.reload.datev_booking_id).to be_nil
      end

      it "refuses connect_single_entry" do
        expect do
          post :connect_single_entry, params: {entry_id: entry.id, booking_id: booking.id}
        end.to raise_error(CanCan::AccessDenied)
        expect(entry.reload.datev_booking_id).to be_nil
      end

      # #reset_links has no route outside development, so it cannot be reached
      # from here at all. What IS assertable is the gate its before_action
      # applies -- and neither read nor write tier passes it.
      it "does not hold the :fin_admin the reset_links gate asks for" do
        expect(Ability.new(auditor.reload)).not_to be_able_to(:fin_admin, DatevBooking)
      end
    end

    context "as an accountant (write tier)" do
      before { sign_in(accountant) }

      it "gets the connect controls back" do
        get :participant_fees

        expect(response).to be_successful
        expect(response.body).to include("Auswahl verbinden")
      end

      it "may connect one booking to one entry" do
        post :connect_single, params: {booking_id: booking.id, entry_id: entry.id}
        expect(entry.reload.datev_booking_id).to eq(booking.id)
      end

      # Wiping every link is the manage tier's, on top of the development-only
      # guard in the action itself (which is also why there is no route to POST
      # to here -- see the auditor's example above).
      it "does not hold the :fin_admin the reset_links gate asks for either" do
        expect(Ability.new(accountant.reload)).not_to be_able_to(:fin_admin, DatevBooking)
      end
    end

    # The "Nicht zugeordnete Beitragsbuchungen" table is a Beitragsbuchungen
    # view, so it follows :show on AccountingEntry -- which is exactly where
    # the two read-only tiers part. The counts, the histogram and the DATEV
    # side above are there for both.
    context "the Beitragsbuchungen section" do
      it "is left out for the plain read tier" do
        sign_in(reader)
        get :participant_fees

        expect(response).to be_successful
        expect(response.body).to include("Nicht zugeordnete Buchungen")
        expect(response.body).not_to include("Nicht zugeordnete Beitragsbuchungen")
        expect(response.body).not_to include(entry.description)
        expect(response.body).not_to include("/fin/ae/#{entry.id}")
      end

      it "is shown to the audit tier" do
        sign_in(auditor)
        get :participant_fees

        expect(response).to be_successful
        expect(response.body).to include("Nicht zugeordnete Beitragsbuchungen")
        expect(response.body).to include(entry.description)
        expect(response.body).to include("/fin/ae/#{entry.id}")
      end
    end
  end

  # The detail pages built from standard_form + input_or_render_attrs. They all
  # share ONE mechanism: #permitted_attrs is empty without the write tier, which
  # makes input_or_render_attrs render read-only values and
  # form_buttons_if_editable drop the Speichern button. Two of them stand for
  # the set (/fin/acc/:id and /fin/tx/:id); the Moss booking, the Ratenplan and
  # the Beitragsbuchung go through exactly the same two helpers.
  describe "the editable finance detail pages" do
    let!(:bank) do
      WsjrdpFinAccount.create!(short_name: "Testkonto", account_identification: "TEST-BANK-1",
        transaction_type: "WsjrdpCamtTransaction", opening_balance_cents: 0,
        opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
    end

    let!(:camt) do
      WsjrdpCamtTransaction.create!(fin_account: bank, camt_type: "CAMT053",
        account_identification: bank.account_identification, account_servicer_reference: "REF-1",
        credit_debit_indication: "DBIT", signed_base_amount: -12.34, base_currency: "EUR",
        value_date: Date.new(2026, 4, 2), description: "Beispielbuchung",
        return_reason: "MS03")
    end

    # Submit buttons of the WRITING forms only -- the layout's quicksearch is a
    # GET form and submits on every page.
    def selects
      Nokogiri::HTML(response.body).css("select").pluck("name")
    end

    def save_buttons
      Nokogiri::HTML(response.body).css("form")
        .reject { |form| form["method"].to_s.casecmp?("get") }
        .flat_map { |form| form.css("button[type=submit], input[type=submit]") }
    end

    describe ::Fin::WsjrdpFinAccountsController, type: :controller do
      render_views

      # The statement's "Person … • Verknüpfte Buchung …" line hangs on ONE
      # rule (Fin::LinkedEntryHelper): may the viewer see the entry's PERSON?
      # The entry's own label carries that person's description and amount, and
      # the link leads to their booking page -- so without it the line keeps the
      # name and loses every link, the entry named by its bare id.
      describe "the linked-entry line" do
        let!(:linked_entry) { entry.tap { |e| e.update!(camt_transaction: camt) } }

        # The statement row's <div> carrying that line (.ae-linked is its
        # "• Verknüpfte Buchung: …" half).
        def linked_line
          Nokogiri::HTML(response.body).at_css("span.ae-linked")&.parent
        end

        def get_statement(person)
          sign_in(person)
          get :show, params: {id: bank.id}
          expect(response).to be_successful
        end

        it "links person and entry for the write tier" do
          get_statement(accountant)

          expect(linked_line).to be_present
          expect(linked_line.text).to include("[#{linked_entry.id}] Teilnahmebeitrag")
          hrefs = linked_line.css("a").pluck("href")
          expect(hrefs).to include("/fin/ae/#{linked_entry.id}")
          expect(hrefs.size).to eq(2) # the person and the entry
        end

        it "gives the auditor the name and a bare id -- no link, no entry data" do
          get_statement(auditor)

          expect(linked_line).to be_present
          expect(linked_line.css("a")).to be_empty
          expect(linked_line.text).to include(people(:yp_a_1).short_full_name_with_nickname)
          expect(linked_line.text).to include("Verknüpfte Buchung: ##{linked_entry.id}")
          expect(linked_line.text).not_to include("Teilnahmebeitrag")
        end
      end

      it "offers the account form to the write tier" do
        sign_in(accountant)
        get :show, params: {id: bank.id}

        expect(response).to be_successful
        expect(save_buttons).not_to be_empty
        expect(response.body).to include("wsjrdp_fin_account[short_name]")
      end

      it "renders it read-only for the read tier -- no inputs, no Speichern" do
        sign_in(auditor)
        get :show, params: {id: bank.id}

        expect(response).to be_successful
        expect(response.body).to include("Testkonto")
        expect(save_buttons).to be_empty
        expect(response.body).not_to include("wsjrdp_fin_account[short_name]")
      end
    end

    describe ::Fin::WsjrdpCamtTransactionsController, type: :controller do
      render_views

      it "offers the transaction form to the write tier" do
        sign_in(accountant)
        get :show, params: {id: camt.id}

        expect(response).to be_successful
        expect(save_buttons).not_to be_empty
        expect(response.body).to include("wsjrdp_camt_transaction[comment]")
      end

      it "renders it read-only for the read tier -- no inputs, no Speichern" do
        sign_in(auditor)
        get :show, params: {id: camt.id}

        expect(response).to be_successful
        expect(response.body).to include("Beispielbuchung")
        expect(save_buttons).to be_empty
        expect(response.body).not_to include("wsjrdp_camt_transaction[comment]")
      end

      # The Retoure-Status select does not go through input_or_render_attrs, so
      # it needs its own gate -- it used to render for everyone.
      it "shows the Retoure-Status as a select only for the write tier" do
        sign_in(accountant)
        get :show, params: {id: camt.id}
        expect(selects).to include("wsjrdp_camt_transaction[return_status]")

        sign_in(auditor)
        get :show, params: {id: camt.id}
        expect(selects).to be_empty
        expect(response.body).to include("In Überprüfung")
      end

      it "refuses the update itself" do
        sign_in(auditor)
        expect do
          put :update, params: {id: camt.id, wsjrdp_camt_transaction: {comment: "x"}}
        end.to raise_error(CanCan::AccessDenied)
        expect(camt.reload.comment).to be_blank
      end
    end

    # The Beitragsbuchung's own page is where the two read-only tiers part: a
    # Beitragsbuchung is one person's fee data, so :finance_read has no :show on
    # AccountingEntry and #authorize_action closes every action here, while
    # :finance_audit -- what an external Kassenprüfer*in holds -- passes. Its
    # toolbar is built by hand rather than through form_buttons, so the write
    # tier's Speichern is asserted separately.
    describe ::Fin::AccountingEntriesController, type: :controller do
      render_views

      it "offers the Speichern button to the write tier" do
        sign_in(accountant)
        get :show, params: {id: entry.id}

        expect(response).to be_successful
        expect(save_buttons).not_to be_empty
        expect(response.body).to include("accounting_entry[comment]")
      end

      it "does not let the plain read tier see a Beitragsbuchung at all" do
        sign_in(reader)

        expect { get :show, params: {id: entry.id} }.to raise_error(CanCan::AccessDenied)
        expect { get :index }.to raise_error(CanCan::AccessDenied)
      end

      it "lets the audit tier read one -- without a link to its person" do
        sign_in(auditor)
        get :show, params: {id: entry.id}

        expect(response).to be_successful
        expect(response.body).to include("Teilnahmebeitrag")
        # Read-only all the same, and no way into the person's own page.
        expect(save_buttons).to be_empty
        expect(response.body).not_to include("accounting_entry[comment]")
        expect(Nokogiri::HTML(response.body).css("#main a").pluck("href"))
          .not_to include("/people/#{entry.subject_id}")
      end

      it "closes the new forms for both read-only tiers (:create)" do
        [reader, auditor].each do |person|
          sign_in(person)

          expect { get :new }.to raise_error(CanCan::AccessDenied)
          expect { get :new_sepa_status }.to raise_error(CanCan::AccessDenied)
        end
      end
    end
  end

  # The "Beiträge" section is REDUCED, not hidden: its overview holds no data
  # and opens at :show, the person-fee list keeps its own :log gate, and the
  # link and the tab to it are left out without :log -- so the read tier is
  # left with the Ratenpläne, which carry no personal data. The nav entry and
  # the area's card on /fin therefore lead somewhere for everyone.
  describe "the Beiträge section" do
    describe ::Fin::FeesController, type: :controller do
      render_views

      def link_hrefs = Nokogiri::HTML(response.body).css("#main a").pluck("href")

      it "shows the plain read tier the Ratenpläne and no person-fee link" do
        sign_in(reader)
        get :index

        expect(response).to be_successful
        expect(link_hrefs).to include("/fin/payment_plans")
        expect(link_hrefs).not_to include("/fin/person_fees")
      end

      it "shows the audit tier both lists" do
        sign_in(auditor)
        get :index

        expect(response).to be_successful
        expect(link_hrefs).to include("/fin/payment_plans").and include("/fin/person_fees")
      end

      it "shows the write tier both lists" do
        sign_in(accountant)
        get :index

        expect(response).to be_successful
        expect(link_hrefs).to include("/fin/payment_plans").and include("/fin/person_fees")
      end
    end

    describe ::Fin::WsjrdpFinPersonFeesController, type: :controller do
      render_views

      it "stays closed to the plain read tier" do
        sign_in(reader)

        expect { get :index }.to raise_error(CanCan::AccessDenied)
      end

      # What :finance_audit exists for -- and the names on it stay plain text,
      # because the tier holds nothing on Person.
      it "is open to the audit tier, with unlinked names" do
        sign_in(auditor)
        get :index

        expect(response).to be_successful
        expect(Nokogiri::HTML(response.body).css("#main a").pluck("href"))
          .not_to include(person_path(people(:yp_a_1)))
      end
    end

    describe ::Fin::WsjrdpPaymentPlansController, type: :controller do
      it "is open to the read tier -- no personal data" do
        sign_in(auditor)
        get :index

        expect(response).to be_successful
      end
    end

    # The tab's if: condition is what the area's card on /fin reads too, so the
    # card loses the same quick link -- and keeps a title link that works.
    describe ::Fin::OverviewController, type: :controller do
      render_views

      it "drops the person-fee quick link from the Beiträge card" do
        sign_in(reader)
        get :index

        expect(response).to be_successful
        hrefs = Nokogiri::HTML(response.body).css("#main a").pluck("href")
        expect(hrefs).to include("/fin/fees").and include("/fin/payment_plans")
        expect(hrefs).not_to include("/fin/person_fees")
      end
    end
  end
end
