# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# A Beitragsbuchung has a reading page (/fin/ae/:id, its detail) and an edit
# page (/fin/ae/:id/edit, the form); a save returns to the reading page. The
# reading page also shows the mails a script sent about a returned direct
# debit (Fin::DebitReturnNoticesHelper).
describe Fin::AccountingEntriesController, type: :controller do
  before_all(setup_fixtures: true) {}

  let_it_be(:manager) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }
  let(:person) { people(:yp_a_1) }

  let_it_be(:entry, refind: true) do
    AccountingEntry.create!(subject: people(:yp_a_1), author: manager,
      amount_cents: -10_300, amount_currency: "EUR", return_reason: "MS03",
      description: "Rücklastschrift", value_date: Date.new(2026, 11, 10),
      booking_date: Date.new(2026, 11, 10))
  end

  before do
    sign_in(manager)
    session[:max_finance_permission] = "finance_manage"
  end

  describe "rendered" do
    render_views

    def doc = Nokogiri::HTML(response.body)

    it "shows the detail with Bearbeiten and no form, the title without markup, the bank transaction linked" do
      tx = WsjrdpCamtTransaction.create!(camt_type: "CAMT053", account_identification: "DE-TEST",
        account_servicer_reference: SecureRandom.hex(8), credit_debit_indication: "DBIT",
        signed_base_amount: -103, base_currency: "EUR", value_date: Date.new(2026, 11, 5),
        description: "Retoure Lastschrift")
      entry.update!(camt_transaction: tx)

      get :show, params: {id: entry.id}

      expect(doc.at_css("a[href='#{edit_accounting_entry_path(entry)}']")).to be_present
      expect(doc.at_css("input[name='accounting_entry[comment]']")).to be_nil
      expect(doc.at_css("title").text).to include("Buchung ##{entry.id}").and include("Rücklastschrift MS03")
      expect(doc.at_css("title").text).not_to include("<span")
      expect(doc.css(".bk-item-detail a[href='#{wsjrdp_camt_transaction_path(tx)}']").size).to eq(2)
      expect(doc.at_css(".fin-debit-return-notices")).to be_nil
    end

    it "shows a mail about the return with its links to the ticket, the address and the log" do
      note = Wsjrdp::LogEntry.note!(entry, main: person, category: "debit_return",
        message: "Per E-Mail über die Rücklastschrift informiert.", whodunnit: nil)
      entry.update!(additional_info: {"debit_return_notifications" => [{
        "sent_at" => "2026-11-12T09:30:00+00:00", "email_to" => ["kim@example.org"],
        "email_subject" => "WSJ27 Einzug 2026-11 Retoure", "debit_return_issue" => "FIN-354",
        "log_version_id" => note.id
      }]})

      get :show, params: {id: entry.id}

      section = doc.at_css(".fin-debit-return-notices")
      expect(section.text).to include("12.11.2026 10:30")
      expect(section.at_css("a[href='mailto:kim@example.org'] + a.fin-copy-tight")).to be_present
      expect(section.at_css("a[href='https://helpdesk.worldscoutjamboree.de/browse/FIN-354']")).to be_present
      expect(section.at_css("a[href='#{log_person_path(person)}'][target=_blank]")).to be_present
    end

    it "edits with the amount disabled" do
      get :edit, params: {id: entry.id}

      expect(doc.at_css("[name='accounting_entry[comment]']")).to be_present
      expect(doc.at_css("input[name='amount_eur_display'][disabled]")).to be_present
      expect(doc.at_css("input[name='accounting_entry[amount_eur]']")).to be_nil
    end
  end

  describe "PUT update" do
    it "leaves the amount as it is and returns to the reading page" do
      put :update, params: {id: entry.id, accounting_entry: {amount_eur: "1", comment: "x"}}

      expect(entry.reload.amount_cents).to eq(-10_300)
      expect(entry.comment).to eq("x")
      expect(response).to redirect_to(accounting_entry_path(entry))
    end
  end
end
