# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The page of ONE bank transaction, split over two pages on the finance detail
# kit (doc/fin/detail_partials.md): /fin/tx/:id reads, /fin/tx/:id/edit changes
# the comment, the person and -- on a return -- the return status. Both render
# the same list of fields (fin/wsjrdp_camt_transactions/_detail), and so does
# a table row that lazy-loads the reading page into its turbo frame. The read
# tiers are covered in finance_read_tier_spec.rb. All names, numbers and
# amounts are invented.
describe Fin::WsjrdpCamtTransactionsController do
  render_views

  let(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  let!(:bank) do
    WsjrdpFinAccount.create!(short_name: "Testkonto", account_identification: "TEST-BANK-1",
      transaction_type: "WsjrdpCamtTransaction", opening_balance_cents: 0,
      opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
  end

  def create_transaction(**attrs)
    WsjrdpCamtTransaction.create!(fin_account: bank, camt_type: "CAMT053",
      account_identification: bank.account_identification, account_servicer_reference: SecureRandom.hex(4),
      credit_debit_indication: "DBIT", signed_base_amount: -12.34, base_currency: "EUR",
      value_date: Date.new(2026, 4, 2), booking_date: Date.new(2026, 4, 3),
      description: "Beispielbuchung", **attrs)
  end

  # A returned direct debit with everything the page can show (the return kind
  # is the database's, derived from the ISO code).
  let!(:returned) do
    create_transaction(return_reason: "MS03",
      bank_transaction_code: "PMNT+IDDT+UPDD", bank_transaction_code_dk: "NRTI+109+00931",
      endtoend_id: "E2E-TEST-1", mandate_id: "MANDAT-TEST-1", status: "BOOK",
      additional_entry_info: "Retourenbelastung", comment: "Testkommentar", subject: people(:yp_a_1),
      cdtr_name: "Testverein e.V.", cdtr_iban: "DE02120300000000202051",
      dbtr_name: "Erika Beispiel", dbtr_iban: "DE02500105170137075030")
  end

  # A plain transaction: no person, no comment, no return, no codes (the status
  # is the column's default).
  let!(:plain) { create_transaction(cdtr_name: "Testverein e.V.") }

  before { sign_in(person) }

  def page = Nokogiri::HTML(response.body)

  def labels = page.css("#main dl.fin-detail-list dt").map { |dt| dt.text.strip }

  # The labels of each block, a block being one list with its rule above.
  def blocks = page.css("#main dl.fin-detail-list").map { |dl| dl.css("dt").map { |dt| dt.text.strip } }

  def writing_forms = page.css("#main form").reject { |form| form["method"].to_s.casecmp?("get") }

  describe "GET #show" do
    it "shows the heading with Bearbeiten and no form" do
      get :show, params: {id: returned.id}

      expect(response).to be_successful
      expect(page.at_css("#main h1").text).to include("Kontobewegung ##{returned.id}")
      expect(page.at_css("#main h1 a[href='#{edit_wsjrdp_camt_transaction_path(returned)}']").text).to eq("Bearbeiten")
      expect(writing_forms).to be_empty
    end

    it "keeps the blocks, their order and their labels" do
      get :show, params: {id: returned.id}

      expect(blocks).to eq([
        ["Konto", "Betrag in Euro", "Währung", "Valuta", "Buchungsdatum", "Verwendungszweck", "Kommentar"],
        ["Beteiligte Person"],
        ["Kundenreferenz", "Mandatsreferenz", "Rückgabe-Grund", "Retoure-Status"],
        ["ISO-Buchungscode", "DK-Buchungscode", "Rückläufer-Art"],
        ["Status", "Zusatz-Information"],
        ["Kreditor Name", "Kreditor IBAN"],
        ["Debitor Name", "Debitor IBAN"]
      ])
    end

    it "shows the signed amount and links the return's page" do
      get :show, params: {id: returned.id}

      expect(response.body).to include("-12,34")
      expect(page.at_css("#main a[href='#{payment_return_path(returned)}']").text).to eq("Rückläufer ##{returned.id}")
    end

    it "lists the Beitragsbuchungen booked for the transaction" do
      entry = AccountingEntry.create!(subject: people(:yp_a_1), author: person, amount_cents: -1234,
        amount_currency: "EUR", description: "Testbuchung", value_date: Date.new(2026, 4, 2),
        camt_transaction: returned)
      get :show, params: {id: returned.id}

      expect(blocks[1]).to eq(["Beteiligte Person", "Buchung"])
      expect(page.at_css("#main a[href='#{accounting_entry_path(entry)}']")).to be_present
    end

    it "leaves out what is blank -- fields, and a block without a field" do
      get :show, params: {id: plain.id}

      expect(blocks).to eq([
        ["Konto", "Betrag in Euro", "Währung", "Valuta", "Buchungsdatum", "Verwendungszweck"],
        ["Status"],
        ["Kreditor Name"]
      ])
    end

    it "shows the reason's code with its meaning behind it" do
      get :show, params: {id: returned.id}

      row = page.css("#main dl.fin-detail-list .row").find { |r| r.at_css("dt").text == "Rückgabe-Grund" }
      expect(row.at_css("dd span.font-monospace").text).to eq("MS03")
      expect(row.at_css("dd span.text-muted.fw-light").text).to eq(Fin::ReturnReasons.label("MS03"))
    end

    it "links addresses and helpdesk tickets in the comment" do
      returned.update!(comment: "siehe FIN-123 und https://example.org/x\nmail@example.org")
      get :show, params: {id: returned.id}

      row = page.css("#main dl.fin-detail-list .row").find { |r| r.at_css("dt").text == "Kommentar" }
      expect(row.css("dd a").pluck("href")).to eq(["https://helpdesk.worldscoutjamboree.de/browse/FIN-123",
        "https://example.org/x", "mailto:mail@example.org"])
    end

    it "puts a copy icon behind the IBANs and BICs" do
      returned.update!(dbtr_bic: "TESTDEFFXXX")
      get :show, params: {id: returned.id}

      expect(page.css("#main a.fin-copy").pluck("data-copy-to-clipboard"))
        .to eq(%w[DE02120300000000202051 DE02500105170137075030 TESTDEFFXXX])
    end

    it "lets every link leave the detail's frame" do
      AccountingEntry.create!(subject: people(:yp_a_1), author: person, amount_cents: -1234,
        amount_currency: "EUR", description: "Testbuchung", value_date: Date.new(2026, 4, 2),
        camt_transaction: returned)
      get :show, params: {id: returned.id}

      inside = page.css("#main turbo-frame a").reject { |a| a["href"] == "#" || a["target"] == "_blank" }
      expect(inside.size).to be >= 6
      expect(inside.pluck("data-turbo-frame").uniq).to eq(["_top"])
    end

    it "names the return that brought a transaction back" do
      came_back = create_transaction(return_reason: "MS03", bank_transaction_code: "PMNT+ICDT+RRTN")
      plain.update!(reversed_by: came_back)
      get :show, params: {id: plain.id}

      expect(labels).to include("Zurückgekommen")
      expect(page.at_css("#main a[href='#{payment_return_path(came_back)}']").text)
        .to include("Rückläufer ##{came_back.id}", "Rücküberweisung")
    end
  end

  # Another page sends the reader here with `return_url` (Fin::ReturnPath).
  describe "return_url" do
    let(:origin) { "/fin/acc/#{bank.id}?page=2" }

    it "leads back from the reading page and hands the path on to the edit page" do
      get :show, params: {id: returned.id, return_url: origin}

      expect(page.at_css("#main a[href='#{origin}']").text.strip).to eq("Zurück")
      expect(page.at_css("#main h1 a")["href"])
        .to eq(edit_wsjrdp_camt_transaction_path(returned, return_url: origin))
    end

    it "keeps it on the edit page" do
      get :edit, params: {id: returned.id, return_url: origin}

      kept = wsjrdp_camt_transaction_path(returned, return_url: origin)
      expect(page.at_css("#main a[href='#{origin}']").text.strip).to eq("Zurück")
      expect(writing_forms.first["action"]).to eq(kept)
      expect(writing_forms.first.at_css("a[href='#{kept}']").text).to eq("Abbrechen")
    end

    it "returns there after a save, and keeps it for Speichern und weiter bearbeiten" do
      patch :update, params: {id: returned.id, return_url: origin, wsjrdp_camt_transaction: {comment: "a"}}
      expect(response).to redirect_to(origin)

      patch :update, params: {id: returned.id, return_url: origin, stay: "1",
                              wsjrdp_camt_transaction: {comment: "b"}}
      expect(response).to redirect_to(edit_wsjrdp_camt_transaction_path(returned, return_url: origin))
    end

    it "ignores a path that leads off the site" do
      get :show, params: {id: returned.id, return_url: "//example.org/x"}
      expect(page.at_css("#main a[href*='example.org']")).to be_nil

      patch :update, params: {id: returned.id, return_url: "https://example.org/x",
                              wsjrdp_camt_transaction: {comment: "c"}}
      expect(response).to redirect_to(wsjrdp_camt_transaction_path(returned))
    end
  end

  # What an expandable table lazy-loads into a row: the reading page, asked for
  # by the row's turbo frame at the table's nesting level.
  describe "as a table row's detail" do
    let(:frame_id) { "bkframe-acc-#{returned.id}" }

    before { request.headers["Turbo-Frame"] = frame_id }

    it "answers as the row's frame, in the compact layout with the inline edit" do
      get :show, params: {id: returned.id, expandable_table_level: 1}

      expect(response).to be_successful
      frame = page.at_css("turbo-frame##{frame_id}")
      expect(frame).to be_present
      expect(page.at_css("h1")).to be_nil
      expect(frame.at_css("dl.row.small")).to be_present
      form = frame.at_css("form[data-fin-editing='false']")
      expect(form["action"]).to eq(wsjrdp_camt_transaction_path(returned))
      expect(form.at_css(".fin-edit-toggle button").text.strip).to eq("Bearbeiten")
      expect(form.at_css("input[data-provide='entity']")["id"]).to eq("camt_transaction_#{returned.id}_subject")
    end

    it "comes back to the row after a save, with the message in it" do
      patch :update, params: {id: returned.id, wsjrdp_camt_transaction: {comment: "in der Zeile"}}
      expect(response).to redirect_to(wsjrdp_camt_transaction_path(returned))
      expect(returned.reload.comment).to eq("in der Zeile")

      get :show, params: {id: returned.id}, flash: {notice: "Kontobewegung #{returned.id} erfolgreich aktualisiert."}
      expect(page.at_css("turbo-frame##{frame_id} .alert").text).to include("erfolgreich aktualisiert")
    end

    it "shows the row again with its form open when the save fails" do
      patch :update, params: {id: returned.id, wsjrdp_camt_transaction: {return_status: "bogus"}}

      expect(response).to have_http_status(422)
      frame = page.at_css("turbo-frame##{frame_id}")
      expect(frame.at_css(".alert").text).to include("Fehler: Retoure-Status ist kein gültiger Wert")
      expect(frame.at_css("form[data-fin-editing='true']")).to be_present
    end
  end

  describe "GET #edit" do
    it "renders the same fields with the inputs in their place" do
      get :edit, params: {id: returned.id}

      expect(response).to be_successful
      expect(blocks.first(3)).to eq([
        ["Konto", "Betrag in Euro", "Währung", "Valuta", "Buchungsdatum", "Verwendungszweck", "Kommentar"],
        ["Beteiligte Person"],
        ["Kundenreferenz", "Mandatsreferenz", "Rückgabe-Grund", "Retoure-Status"]
      ])
      form = writing_forms.first
      expect(form["action"]).to eq(wsjrdp_camt_transaction_path(returned))
      expect(form.at_css("textarea[name='wsjrdp_camt_transaction[comment]']").text.strip).to eq("Testkommentar")
      expect(form.at_css("input[name='wsjrdp_camt_transaction[subject_id]']")["value"]).to eq(people(:yp_a_1).id.to_s)
      search = form.at_css("input[name='wsjrdp_camt_transaction[subject]'][data-provide='entity']")
      expect(search["data-id-field"]).to eq(form.at_css("input[name='wsjrdp_camt_transaction[subject_id]']")["id"])
      expect(form.at_css("select[name='wsjrdp_camt_transaction[return_status]'] option[selected]")["value"])
        .to eq("in_review")
      expect(form.css("button[type=submit]").pluck("name")).to eq(%w[save stay])
      expect(form.at_css("a[href='#{wsjrdp_camt_transaction_path(returned)}']").text).to eq("Abbrechen")
      expect(response.body).to include("Bisheriger Wert")
    end

    it "offers the blank comment and person, and no return status without a return" do
      get :edit, params: {id: plain.id}

      expect(blocks.first(2)).to eq([
        ["Konto", "Betrag in Euro", "Währung", "Valuta", "Buchungsdatum", "Verwendungszweck", "Kommentar"],
        ["Beteiligte Person"]
      ])
      expect(page.at_css("select[name='wsjrdp_camt_transaction[return_status]']")).to be_nil
      expect(response.body).not_to include("Bisheriger Wert")
    end
  end

  describe "PATCH #update" do
    it "saves and goes back to the reading page" do
      patch :update, params: {id: returned.id, save: "1", wsjrdp_camt_transaction: {
        comment: "Neuer Kommentar", return_status: "paid",
        subject: people(:yp_a_1).to_s, subject_id: people(:yp_a_1).id
      }}

      expect(response).to redirect_to(wsjrdp_camt_transaction_path(returned))
      expect(returned.reload).to have_attributes(comment: "Neuer Kommentar", return_status: "paid",
        subject: people(:yp_a_1))
    end

    it "comes back to the edit page for Speichern und weiter bearbeiten" do
      patch :update, params: {id: returned.id, stay: "1", wsjrdp_camt_transaction: {comment: "Weiter"}}

      expect(response).to redirect_to(edit_wsjrdp_camt_transaction_path(returned))
      expect(returned.reload.comment).to eq("Weiter")
    end

    it "leaves the person alone when the request does not carry the field" do
      patch :update, params: {id: returned.id, wsjrdp_camt_transaction: {comment: "nur der Kommentar"}}

      expect(returned.reload).to have_attributes(comment: "nur der Kommentar", subject: people(:yp_a_1))
    end

    # A save that fails its validation: the edit page again, the reasons as an
    # alert, nothing saved.
    describe "validation" do
      def expect_refused(message)
        expect(response).to have_http_status(422)
        expect(page.at_css(".alert-danger").text).to include("Fehler: #{message}")
        expect(writing_forms).not_to be_empty
      end

      it "refuses a return status there is none of" do
        patch :update, params: {id: returned.id, wsjrdp_camt_transaction: {return_status: "bogus", comment: "x"}}

        expect_refused("Retoure-Status ist kein gültiger Wert")
        expect(returned.reload).to have_attributes(return_status: "in_review", comment: "Testkommentar")
      end

      it "refuses a person that does not exist" do
        patch :update, params: {id: plain.id, wsjrdp_camt_transaction: {subject: "Niemand", subject_id: 0}}

        expect_refused("Beteiligte Person wurde nicht gefunden")
        expect(plain.reload.subject_id).to be_nil
      end

      it "refuses a name that was typed but not chosen, and keeps it in the field" do
        patch :update, params: {id: returned.id, wsjrdp_camt_transaction: {subject: "Erika Tippfehler", subject_id: ""}}

        expect_refused("Beteiligte Person muss aus der Vorschlagsliste gewählt werden")
        expect(page.at_css("input[name='wsjrdp_camt_transaction[subject]']")["value"]).to eq("Erika Tippfehler")
        expect(response.body).to include("Bisheriger Wert")
        expect(returned.reload.subject).to eq(people(:yp_a_1))
      end
    end

    it "links and unlinks the person" do
      patch :update, params: {id: plain.id, wsjrdp_camt_transaction: {
        subject: people(:yp_a_1).to_s, subject_id: people(:yp_a_1).id
      }}
      expect(plain.reload.subject).to eq(people(:yp_a_1))

      patch :update, params: {id: plain.id, wsjrdp_camt_transaction: {subject: "", subject_id: people(:yp_a_1).id}}
      expect(plain.reload.subject).to be_nil
    end
  end
end
