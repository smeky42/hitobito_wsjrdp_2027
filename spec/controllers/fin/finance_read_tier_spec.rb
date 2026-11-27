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
#     unlinking and for the DATEV booking's field edits, :admin_finance for the
#     dev-only reset and for the account form's own master data),
#   * the page offers no control that would trigger one: the detail pages built
#     on #permitted_attrs get none, and the views that decide by themselves are
#     rendered.
#
# The second half is not cosmetic: a Speichern button that can only answer 403
# is what turns a permission boundary into a bug report.
describe "finance read tier (Buchhaltung / Abstimmung)" do
  before_all(setup_fixtures: true) {}

  let_it_be(:auditor, refind: true) do
    extern = Group::Extern.create!(name: "Extern", parent: groups(:root))
    Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: extern).person
  end
  let_it_be(:reader, refind: true) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }
  let_it_be(:accountant, refind: true) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let_it_be(:fin_admin, refind: true) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }

  let_it_be(:batch) do
    DatevBookingBatch.create!(consultant_number: "1", client_number: "2",
      label: "Teststapel", period_from: Date.new(2026, 1, 1),
      period_to: Date.new(2026, 1, 31), financial_year_start: Date.new(2026, 1, 1),
      primanota_number: "01-2026/0001", import_export: "import")
  end

  let_it_be(:booking, refind: true) do
    DatevBooking.create!(batch: batch, buchungs_guid: SecureRandom.uuid,
      account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "41030", offsetting_account_kind: "INCOME",
      cost_center_number: "9500",
      base_amount: 100, transaction_amount: 100, debit_credit: "D",
      base_currency: "EUR", booking_date: Date.new(2026, 2, 1),
      posting_text: "Testbuchung Alpha")
  end

  let_it_be(:entry, refind: true) do
    AccountingEntry.create!(subject: people(:yp_a_1), author: accountant,
      amount_cents: 10_000, amount_currency: "EUR",
      description: "Teilnahmebeitrag", value_date: Date.new(2026, 2, 1),
      booking_date: Date.new(2026, 2, 1))
  end

  def doc = Nokogiri::HTML(response.body)

  def main_hrefs = doc.css("#main a").pluck("href")

  def permitted_attrs = controller.send(:permitted_attrs)

  describe ::Fin::BookingsController, type: :controller do
    # The forms themselves, not the page text: the detail's confirm JS names
    # both CSS classes in a string, so a plain body match would always hit.
    def forms(css) = doc.css("form#{css}")

    context "as an external auditor (read tier)" do
      before { sign_in(auditor) }

      describe "the booking detail" do
        render_views

        it "carries no unlink button, no connect widget, no field input and no way to the edit page" do
          get :show, params: {id: booking.id}

          aggregate_failures do
            expect(response).to be_successful
            expect(forms(".bk-connect-entry-form")).to be_empty
            expect(forms(".bk-unlink-form")).to be_empty
            expect(response.body).to include("nicht verknüpft")
            expect(response.body).not_to include("datev_booking[secondary_cost_center_number]")
            expect(response.body).not_to include("datev_booking[comment]")
            expect(response.body).not_to include("datev_booking[user_comment]")
            expect(response.body).not_to include(edit_booking_path(booking))
          end
        end
      end

      # The other half of the same boundary: the edit page itself, which the
      # read tier must not reach even by typing its URL.
      it "refuses the edit page" do
        expect { get :edit, params: {id: booking.id} }.to raise_error(CanCan::AccessDenied)
      end

      it "refuses to edit a comment" do
        expect do
          patch :update, params: {id: booking.id, datev_booking: {user_comment: "x"}}
        end.to raise_error(CanCan::AccessDenied)
        expect(booking.reload.user_comment).to eq("")
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

      describe "the booking detail" do
        render_views

        it "still carries the connect widget" do
          get :show, params: {id: booking.id}
          expect(forms(".bk-connect-entry-form")).not_to be_empty
        end
      end

      it "connects" do
        patch :update, params: {id: booking.id, datev_booking: {accounting_entry_id: entry.id}}
        expect(entry.reload.datev_booking_id).to eq(booking.id)
      end

      # The field edits are the write tier's -- the same gate the detail view
      # asks before it builds the form.
      it "may edit the booking fields" do
        patch :update, params: {id: booking.id, datev_booking: {sub_cost_center_number: "X1"}}
        expect(booking.reload.sub_cost_center_number).to eq("X1")
      end
    end

    context "as a finance admin" do
      # The manage tier has to be picked for the session; without a pick even
      # a FinanceManager works at the write tier
      # (doc/roles.md -> "The finance cap").
      before do
        sign_in(fin_admin)
        session[:max_finance_permission] = "finance_manage"
        WsjrdpSubCostCenter.create!(cost_center_number: "9500", number: "X1", name: "Teil X")
      end

      # The sub cost center of a booking is the pair (cost_center_number,
      # sub_cost_center_number); the row it names lives under the booking's own
      # cost center (doc/fin/sub_cost_centers.md).
      it "may edit the booking fields" do
        patch :update, params: {id: booking.id, datev_booking: {sub_cost_center_number: "X1"}}
        expect(booking.reload.sub_cost_center_number).to eq("X1")
      end

      # "nicht gesetzt" of the select posts the empty string; the column holds
      # NULL for a booking without a sub cost center, never "".
      it "clears the sub cost center to NULL" do
        booking.update_column(:sub_cost_center_number, "X1")

        patch :update, params: {id: booking.id, datev_booking: {sub_cost_center_number: ""}}
        expect(booking.reload.sub_cost_center_number).to be_nil
      end
    end
  end

  describe ::Fin::ReconciliationController, type: :controller do
    context "as an external auditor (read tier)" do
      before { sign_in(auditor) }

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
      it "does not hold the :admin_finance the reset_links gate asks for" do
        expect(Ability.new(auditor)).not_to be_able_to(:admin_finance, DatevBooking)
      end
    end

    context "as an accountant (write tier)" do
      before { sign_in(accountant) }

      describe "the page" do
        render_views

        it "gets the connect controls back" do
          get :participant_fees
          expect(response.body).to include("Auswahl verbinden")
        end
      end

      it "may connect one booking to one entry" do
        post :connect_single, params: {booking_id: booking.id, entry_id: entry.id}
        expect(entry.reload.datev_booking_id).to eq(booking.id)
      end

      # Wiping every link is the manage tier's, on top of the development-only
      # guard in the action itself.
      it "does not hold the :admin_finance the reset_links gate asks for either" do
        expect(Ability.new(accountant)).not_to be_able_to(:admin_finance, DatevBooking)
      end
    end

    # The "Nicht zugeordnete Beitragsbuchungen" table is a Beitragsbuchungen
    # view, so it follows :show on AccountingEntry -- which is exactly where
    # the two read-only tiers part. The counts, the histogram and the DATEV
    # side above are there for both.
    context "the Beitragsbuchungen section" do
      render_views

      it "is left out for the plain read tier" do
        sign_in(reader)
        get :participant_fees

        aggregate_failures do
          expect(response.body).to include("Nicht zugeordnete Buchungen")
          expect(response.body).not_to include("Nicht zugeordnete Beitragsbuchungen")
          expect(response.body).not_to include(entry.description)
          expect(response.body).not_to include("/fin/ae/#{entry.id}")
        end
      end

      it "is shown to the audit tier, on a reading view without connect controls or checkboxes" do
        sign_in(auditor)
        get :participant_fees

        aggregate_failures do
          expect(response).to be_successful
          expect(response.body).to include("Nicht zugeordnete Beitragsbuchungen")
          expect(response.body).to include(entry.description)
          expect(response.body).to include("/fin/ae/#{entry.id}")
          expect(response.body).not_to include("Auswahl verbinden")
          expect(response.body).not_to include("bk-connect-form")
          expect(response.body).not_to include("ae-connect-form")
          expect(response.body).not_to include("Alle Verknüpfungen zurücksetzen")
        end
      end
    end
  end

  # The detail pages built from standard_form + input_or_render_attrs. They all
  # share ONE mechanism: #permitted_attrs is empty without the write tier, which
  # makes input_or_render_attrs render read-only values and
  # form_buttons_if_editable drop the Speichern button -- so #permitted_attrs is
  # what these examples ask.
  describe "the editable finance detail pages" do
    let_it_be(:bank) do
      WsjrdpFinAccount.create!(short_name: "Testkonto", account_identification: "TEST-BANK-1",
        transaction_type: "WsjrdpCamtTransaction", opening_balance_cents: 0,
        opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
    end

    let_it_be(:camt, refind: true) do
      WsjrdpCamtTransaction.create!(fin_account: bank, camt_type: "CAMT053",
        account_identification: bank.account_identification, account_servicer_reference: "REF-1",
        credit_debit_indication: "DBIT", signed_base_amount: -12.34, base_currency: "EUR",
        value_date: Date.new(2026, 4, 2), description: "Beispielbuchung",
        return_reason: "MS03")
    end

    describe ::Fin::WsjrdpFinAccountsController, type: :controller do
      it "offers the account form to the write tier" do
        sign_in(accountant)
        get :edit, params: {id: bank.id}

        expect(response).to be_successful
        expect(permitted_attrs).to include(:short_name)
      end

      # The form is editable from the write tier up, but the master data of the
      # account -- what it is, which bank, which opening balance -- stays the
      # manage tier's. A rejected field is DROPPED by #permit, not refused, so
      # nothing but the stored value tells the two apart.
      it "lets the write tier rename the account and nothing else" do
        sign_in(accountant)

        patch :update, params: {id: bank.id, wsjrdp_fin_account: {
          short_name: "Umbenannt", iban: "DE02120300000000202051",
          account_identification: "GEAENDERT", status: "closed"
        }}

        bank.reload
        expect(bank.short_name).to eq("Umbenannt")
        expect(bank.iban).to be_nil
        expect(bank.account_identification).to eq("TEST-BANK-1")
      end

      it "renders it read-only for the read tier" do
        sign_in(auditor)
        get :show, params: {id: bank.id}

        expect(response).to be_successful
        expect(permitted_attrs).to be_empty
      end
    end

    # The page is split (the finance detail kit): the reading page carries no
    # form for anybody, the write tier reaches the form through "Bearbeiten".
    describe ::Fin::WsjrdpCamtTransactionsController, type: :controller do
      it "offers the edit page with comment and Retoure-Status to the write tier" do
        sign_in(accountant)
        get :edit, params: {id: camt.id}

        expect(response).to be_successful
        expect(permitted_attrs).to include(:comment, :return_status)
      end

      it "refuses the read tier the edit page" do
        sign_in(auditor)
        expect { get :edit, params: {id: camt.id} }.to raise_error(CanCan::AccessDenied)
      end

      it "refuses the update itself" do
        sign_in(auditor)
        expect do
          put :update, params: {id: camt.id, wsjrdp_camt_transaction: {comment: "x"}}
        end.to raise_error(CanCan::AccessDenied)
        expect(camt.reload.comment).to be_blank
      end

      describe "the reading page" do
        render_views

        it "leads the write tier to the edit page" do
          sign_in(accountant)
          get :show, params: {id: camt.id}

          expect(response.body).to include(edit_wsjrdp_camt_transaction_path(camt))
        end

        it "offers the read tier no Bearbeiten" do
          sign_in(auditor)
          get :show, params: {id: camt.id}

          aggregate_failures do
            expect(response).to be_successful
            expect(response.body).not_to include(edit_wsjrdp_camt_transaction_path(camt))
          end
        end
      end
    end

    # The Beitragsbuchung's own page is where the two read-only tiers part: a
    # Beitragsbuchung is one person's fee data, so :finance_read has no :show on
    # AccountingEntry and #authorize_action closes every action here, while
    # :finance_audit -- what an external Kassenprüfer*in holds -- passes.
    describe ::Fin::AccountingEntriesController, type: :controller do
      it "offers the form to the write tier" do
        sign_in(accountant)
        get :edit, params: {id: entry.id}

        expect(response).to be_successful
        expect(permitted_attrs).to include(:comment)
      end

      it "does not let the plain read tier see a Beitragsbuchung" do
        sign_in(reader)
        expect { get :show, params: {id: entry.id} }.to raise_error(CanCan::AccessDenied)
      end

      it "does not let the plain read tier list the Beitragsbuchungen" do
        sign_in(reader)
        expect { get :index }.to raise_error(CanCan::AccessDenied)
      end

      it "lets the audit tier read one, read-only" do
        sign_in(auditor)
        get :show, params: {id: entry.id}

        expect(response).to be_successful
        expect(permitted_attrs).to be_empty
      end

      it "refuses the audit tier the edit page" do
        sign_in(auditor)
        expect { get :edit, params: {id: entry.id} }.to raise_error(CanCan::AccessDenied)
      end

      it "closes the new forms for both read-only tiers (:create)" do
        aggregate_failures do
          [reader, auditor].each do |person|
            expect(Ability.new(person)).not_to be_able_to(:create, AccountingEntry)
          end
        end
      end

      it "refuses the new form" do
        sign_in(auditor)
        expect { get :new }.to raise_error(CanCan::AccessDenied)
      end

      it "refuses the new SEPA status form" do
        sign_in(reader)
        expect { get :new_sepa_status }.to raise_error(CanCan::AccessDenied)
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

      it "shows the plain read tier the Ratenpläne and no person-fee link" do
        sign_in(reader)
        get :index

        aggregate_failures do
          expect(response).to be_successful
          expect(main_hrefs).to include("/fin/payment_plans")
          expect(main_hrefs).not_to include("/fin/person_fees")
        end
      end

      # The link stands on :log, which the audit tier holds and the read tier
      # does not.
      it "keeps the person-fee link for the audit tier" do
        aggregate_failures do
          expect(Ability.new(auditor)).to be_able_to(:log, WsjrdpFinAccount)
          expect(Ability.new(reader)).not_to be_able_to(:log, WsjrdpFinAccount)
        end
      end
    end

    describe ::Fin::WsjrdpFinPersonFeesController, type: :controller do
      it "stays closed to the plain read tier" do
        sign_in(reader)

        expect { get :index }.to raise_error(CanCan::AccessDenied)
      end

      # What :finance_audit exists for; the names on it stay plain text,
      # because the tier holds nothing on Person (Fin::LinkedEntryHelper).
      it "is open to the audit tier" do
        sign_in(auditor)
        get :index

        expect(response).to be_successful
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
      it "drops the person-fee quick link from the Beiträge card" do
        sign_in(reader)
        get :index

        fees = controller.view_context.fin_areas.find { |area| area.key == :fees }
        paths = [fees.path, *fees.tabs.map(&:last)]
        aggregate_failures do
          expect(paths).to include("/fin/fees", "/fin/payment_plans")
          expect(paths).not_to include("/fin/person_fees")
        end
      end
    end
  end

  # The Verwaltung area configures the section itself. Both of its tabs carry
  # the :configure_finance gate, which is what keeps the area off the /fin page
  # and out of the left sub-navigation for everybody else -- the card would
  # otherwise lead to two pages that answer 403.
  describe "the Verwaltung section" do
    describe ::Fin::OverviewController, type: :controller do
      def admin_area = controller.view_context.fin_areas.find { |area| area.key == :admin }

      it "is not on the auditor's entry page" do
        sign_in(auditor)
        get :index

        expect(admin_area).to be_nil
      end

      it "is there for a CMT admin" do
        sign_in(Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person)
        get :index

        expect([admin_area.path, *admin_area.tabs.map(&:last)])
          .to include("/fin/admin/finance_groups", "/fin/admin/group_cost_centers")
      end
    end
  end
end
