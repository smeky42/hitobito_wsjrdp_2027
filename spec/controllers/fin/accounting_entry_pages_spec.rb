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
  render_views

  let(:manager) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }
  let(:person) { people(:yp_a_1) }

  let!(:entry) do
    AccountingEntry.create!(subject: person, author: manager,
      amount_cents: -10_300, amount_currency: "EUR", return_reason: "MS03",
      description: "Rücklastschrift", value_date: Date.new(2026, 11, 10),
      booking_date: Date.new(2026, 11, 10))
  end

  before do
    sign_in(manager)
    session[:max_finance_permission] = "finance_manage"
  end

  def doc = Nokogiri::HTML(response.body)

  def notices_text = doc.at_css(".fin-debit-return-notices")&.text&.squish

  describe "GET show" do
    it "shows the detail with Bearbeiten, and no form" do
      get :show, params: {id: entry.id}

      expect(response).to be_successful
      expect(doc.at_css(".bk-item-detail").text).to include("Rücklastschrift").and include("MS03")
      # The detail kit's list, not cells.
      expect(doc.css(".bk-item-detail dl.fin-detail-list dt").map { |dt| dt.text.squish })
        .to include("Buchungsdatum", "Betrag", "Rückgabegrund")
      expect(doc.at_css("a[href='#{edit_accounting_entry_path(entry)}']").text).to eq("Bearbeiten")
      expect(doc.at_css("input[name='accounting_entry[comment]']")).to be_nil
    end

    it "titles the page with the muted number and a summary, the tab in plain text" do
      get :show, params: {id: entry.id}

      h1 = doc.at_css(".content-header h1")
      expect(h1.at_css("span.text-muted.fw-light").text).to eq("Buchung ##{entry.id}")
      expect(h1.text.squish).to include("Rücklastschrift MS03").and include("10.11.2026")
      expect(doc.at_css("title").text).to include("Buchung ##{entry.id} · ").and include("Rücklastschrift MS03")
      expect(doc.at_css("title").text).not_to include("<span")
    end

    it "uses h2 for the section headings" do
      entry.update!(dbtr_name: "Kim Example", cdtr_name: "Kontingent")
      get :show, params: {id: entry.id}

      expect(doc.css(".bk-item-detail h2").map(&:text))
        .to eq(["Debitor (Zahlungspflichtig)", "Kreditor (Zahlungsempfänger*in)"])
    end

    it "shows the comment under the purpose, linked, and only when there is one" do
      get :show, params: {id: entry.id}
      expect(doc.css(".fin-detail-list dt").map(&:text)).not_to include("Kommentar")

      entry.update!(comment: "Siehe FIN-354 und https://example.org/x")
      get :show, params: {id: entry.id}

      labels = doc.css(".fin-detail-list dt").map(&:text)
      expect(labels.index("Kommentar")).to eq(labels.index("Verwendungszweck") + 1)
      row = doc.css(".fin-detail-list .row").find { |r| r.at_css("dt").text == "Kommentar" }
      expect(row.css("a").pluck("href"))
        .to include("https://helpdesk.worldscoutjamboree.de/browse/FIN-354", "https://example.org/x")
    end

    it "shows no mail section without a mail" do
      get :show, params: {id: entry.id}

      expect(notices_text).to be_nil
    end

    context "with a mail about the return" do
      let!(:note) do
        Wsjrdp::LogEntry.note!(entry, main: person, category: "debit_return",
          message: "Per E-Mail über die Rücklastschrift informiert.", whodunnit: nil)
      end

      before do
        entry.update!(additional_info: {"debit_return_notifications" => [{
          "sent_at" => "2026-11-12T09:30:00+00:00",
          "email_to" => ["kim@example.org"], "email_cc" => ["parent@example.org"],
          "email_subject" => "WSJ27 Einzug 2026-11 Retoure",
          "email_message_id" => "<abc@example.org>",
          "debit_return_issue" => "FIN-354", "log_version_id" => note.id
        }]})
      end

      it "shows when, to whom, the subject, the ticket and the log note" do
        get :show, params: {id: entry.id}

        expect(notices_text).to include("12.11.2026 10:30")
          .and include("WSJ27 Einzug 2026-11 Retoure")
          .and include("kim@example.org").and include("parent@example.org")
          .and include("FIN-354")
          .and include("Per E-Mail über die Rücklastschrift informiert.")
          .and include("Message-ID <abc@example.org>")
        section = doc.at_css(".fin-debit-return-notices")
        expect(section.at_css("a[href='mailto:kim@example.org'] + a.fin-copy-tight[data-copy-to-clipboard='kim@example.org']"))
          .to be_present
        expect(section.css("dl.fin-detail-list dt").map(&:text)).to include("Versendet", "Betreff", "Ticket")
        expect(section.at_css("a[href='https://helpdesk.worldscoutjamboree.de/browse/FIN-354']")).to be_present
        expect(section.at_css("a[href='#{log_person_path(person)}'][target=_blank]")).to be_present
        # The note as the log shows it: the category label in italics, no "Log:" prefix.
        note_row = section.css(".row").find { |r| r.at_css("dt").text == "Log-Eintrag" }
        expect(note_row.at_css("dd i").text).to eq("Rücklastschrift")
        expect(note_row.at_css("dd").text.squish).to start_with("Rücklastschrift: Per E-Mail")
      end

      it "also shows a note that no element of additional_info names" do
        Wsjrdp::LogEntry.note!(entry, main: person, category: "debit_return",
          message: "Zweite Mail.", data: {"email_subject" => "Erinnerung"}, whodunnit: nil)
        get :show, params: {id: entry.id}

        expect(notices_text).to include("WSJ27 Einzug 2026-11 Retoure").and include("Erinnerung")
          .and include("Zweite Mail.")
      end

      it "leaves out notes of another category" do
        Wsjrdp::LogEntry.note!(entry, main: person, category: "pre_notification",
          message: "Vorab informiert.", whodunnit: nil)
        get :show, params: {id: entry.id}

        expect(notices_text).not_to include("Vorab informiert.")
      end
    end
  end

  describe "GET edit" do
    it "shows the form, the amount disabled, in the order of the reading page" do
      get :edit, params: {id: entry.id}

      expect(response).to be_successful
      expect(doc.at_css("input[name='accounting_entry[comment]'], textarea[name='accounting_entry[comment]']"))
        .to be_present
      expect(doc.at_css("input[name='amount_eur_display'][disabled]")).to be_present
      expect(doc.at_css("input[name='accounting_entry[amount_eur]']")).to be_nil
      text = doc.at_css("#main").text.squish
      order = ["Valuta", "Verwendungszweck", "Kommentar", "Betrag", "SEPA-Lastschrift",
        "Debitor (Zahlungspflichtig)", "Kreditor (Zahlungsempfänger*in)", "Erstellt"]
      expect(order.map { |label| text.index(label) }).to eq(order.map { |label| text.index(label) }.sort)
    end
  end

  describe "the links" do
    let(:tx) do
      WsjrdpCamtTransaction.create!(camt_type: "CAMT053", account_identification: "DE-TEST",
        account_servicer_reference: SecureRandom.hex(8), credit_debit_indication: "DBIT",
        signed_base_amount: -103, base_currency: "EUR", value_date: Date.new(2026, 11, 5),
        description: "Retoure Lastschrift")
    end

    it "links the bank transaction with a new-tab icon and its summary" do
      entry.update!(camt_transaction: tx)
      get :show, params: {id: entry.id}

      row = doc.css(".fin-detail-list .row").find { |r| r.at_css("dt").text == "Bank-Transaktion" }
      expect(row.css("a").pluck("href")).to eq([wsjrdp_camt_transaction_path(tx)] * 2)
      expect(row.at_css("a[target=_blank]")).to be_present
      expect(row.text.squish).to include("05.11.2026").and include("Retoure Lastschrift")
    end
  end

  describe "PUT update" do
    it "leaves the amount as it is" do
      put :update, params: {id: entry.id, accounting_entry: {amount_eur: "1", comment: "x"}}

      expect(entry.reload.amount_cents).to eq(-10_300)
      expect(entry.comment).to eq("x")
    end

    it "returns to the reading page" do
      put :update, params: {id: entry.id, accounting_entry: {comment: "Ticket FIN-354"}}

      expect(response).to redirect_to(accounting_entry_path(entry))
      expect(entry.reload.comment).to eq("Ticket FIN-354")
    end
  end
end
