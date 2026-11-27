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
# the comment, the person and -- on a return -- the return status. A table row
# lazy-loads the reading page into its turbo frame. The read tiers are covered
# in finance_read_tier_spec.rb. All names, numbers and amounts are invented.
describe Fin::WsjrdpCamtTransactionsController do
  before_all(setup_fixtures: true) {}

  let_it_be(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  let_it_be(:bank) do
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

  # A returned direct debit with everything the page can show.
  let_it_be(:returned, refind: true) do
    create_transaction(return_reason: "MS03",
      bank_transaction_code: "PMNT+IDDT+UPDD", bank_transaction_code_dk: "NRTI+109+00931",
      endtoend_id: "E2E-TEST-1", mandate_id: "MANDAT-TEST-1", status: "BOOK",
      additional_entry_info: "Retourenbelastung", comment: "Testkommentar", subject: people(:yp_a_1),
      cdtr_name: "Testverein e.V.", cdtr_iban: "DE02120300000000202051",
      dbtr_name: "Erika Beispiel", dbtr_iban: "DE02500105170137075030", dbtr_bic: "TESTDEFFXXX")
  end

  # A plain transaction: no person, no comment, no return, no codes.
  let_it_be(:plain, refind: true) { create_transaction(cdtr_name: "Testverein e.V.") }

  let(:origin) { "/fin/acc/#{bank.id}?page=2" }

  before { sign_in(person) }

  describe "rendered" do
    render_views

    def page = Nokogiri::HTML(response.body)

    def labels = page.css("#main dl.fin-detail-list dt").map { |dt| dt.text.strip }

    def writing_forms = page.css("#main form").reject { |form| form["method"].to_s.casecmp?("get") }

    # On a return the other side is the payer of the direct debit.
    it "shows a return with its payer, its links out of the frame and no form" do
      entry = AccountingEntry.create!(subject: people(:yp_a_1), author: person, amount_cents: -1234,
        amount_currency: "EUR", description: "Testbuchung", value_date: Date.new(2026, 4, 2),
        camt_transaction: returned)

      get :show, params: {id: returned.id, return_url: origin}

      gegenseite = page.css("#main *").find { |el| el.children.one? && el.text.strip == "Gegenseite" }
      expect(gegenseite.parent.text).to include("Erika Beispiel")
      expect(page.at_css("#main a[href='#{payment_return_path(returned)}']")).to be_present
      expect(page.at_css("#main a[href='#{accounting_entry_path(entry)}']")).to be_present
      expect(page.at_css("#main a[href='#{origin}']")).to be_present
      expect(page.at_css("#main h1 a")["href"]).to eq(edit_wsjrdp_camt_transaction_path(returned, return_url: origin))
      expect(page.css("#main a.fin-copy").pluck("data-copy-to-clipboard"))
        .to eq(%w[DE02120300000000202051 DE02500105170137075030 TESTDEFFXXX])
      inside = page.css("#main turbo-frame a").reject { |a| a["href"] == "#" || a["target"] == "_blank" }
      expect(inside.pluck("data-turbo-frame").uniq).to eq(["_top"])
      expect(writing_forms).to be_empty
    end

    it "names the return that brought a transaction back and leaves blank fields out" do
      came_back = create_transaction(return_reason: "MS03", bank_transaction_code: "PMNT+ICDT+RRTN")
      plain.update!(reversed_by: came_back)

      get :show, params: {id: plain.id}

      expect(labels).to include("Zurückgekommen")
      expect(labels).not_to include("Kommentar", "Beteiligte Person", "Retoure-Status")
      expect(page.at_css("#main a[href='#{payment_return_path(came_back)}']")).to be_present
    end

    # The "Alle" table's rows are keyed "camt-<id>": the detail answers in that
    # frame, but not in one that ends in another record's id.
    it "ignores a frame of another record" do
      request.headers["Turbo-Frame"] = "bkframe-at-camt-#{returned.id}"

      get :show, params: {id: plain.id, expandable_table_level: 1}

      expect(page.at_css("turbo-frame#bkframe-at-camt-#{returned.id}")).to be_nil
    end

    describe "as a table row's detail" do
      before { request.headers["Turbo-Frame"] = "bkframe-at-camt-#{returned.id}" }

      def frame = page.at_css("turbo-frame#bkframe-at-camt-#{returned.id}")

      it "answers as the row's frame with the inline edit" do
        get :show, params: {id: returned.id, expandable_table_level: 1}

        expect(page.at_css("h1")).to be_nil
        form = frame.at_css("form[data-fin-editing='false']")
        expect(form["action"]).to eq(wsjrdp_camt_transaction_path(returned))
        expect(form.at_css("input[data-provide='entity']")["id"]).to eq("camt_transaction_#{returned.id}_subject")
      end

      it "shows the row again with its form open when the save fails" do
        patch :update, params: {id: returned.id, wsjrdp_camt_transaction: {return_status: "bogus"}}

        expect(response).to have_http_status(422)
        expect(frame.at_css(".alert")).to be_present
        expect(frame.at_css("form[data-fin-editing='true']")).to be_present
      end
    end

    it "edits a return with the person, the return status, both submits and the way back" do
      get :edit, params: {id: returned.id, return_url: origin}

      kept = wsjrdp_camt_transaction_path(returned, return_url: origin)
      form = writing_forms.first
      expect(form["action"]).to eq(kept)
      expect(form.at_css("a[href='#{kept}']")).to be_present
      expect(form.at_css("textarea[name='wsjrdp_camt_transaction[comment]']").text.strip).to eq("Testkommentar")
      search = form.at_css("input[name='wsjrdp_camt_transaction[subject]'][data-provide='entity']")
      expect(search["data-id-field"]).to eq(form.at_css("input[name='wsjrdp_camt_transaction[subject_id]']")["id"])
      expect(form.at_css("select[name='wsjrdp_camt_transaction[return_status]'] option[selected]")["value"])
        .to eq("in_review")
      expect(form.css("button[type=submit]").pluck("name")).to eq(%w[save stay])
    end

    it "offers no return status without a return" do
      get :edit, params: {id: plain.id}

      expect(page.at_css("select[name='wsjrdp_camt_transaction[return_status]']")).to be_nil
      expect(page.at_css("textarea[name='wsjrdp_camt_transaction[comment]']")).to be_present
    end

    # A name typed but not chosen stays in the field.
    it "keeps a typed but unchosen name in the field of the refused edit page" do
      patch :update, params: {id: returned.id, wsjrdp_camt_transaction: {subject: "Erika Tippfehler", subject_id: ""}}

      expect(response).to have_http_status(422)
      expect(page.at_css("input[name='wsjrdp_camt_transaction[subject]']")["value"]).to eq("Erika Tippfehler")
    end
  end

  # Another page sends the reader here with `return_url` (Fin::ReturnPath).
  describe "return_url" do
    it "returns there after a save" do
      patch :update, params: {id: returned.id, return_url: origin, wsjrdp_camt_transaction: {comment: "a"}}

      expect(response).to redirect_to(origin)
    end

    it "keeps it for Speichern und weiter bearbeiten" do
      patch :update, params: {id: returned.id, return_url: origin, stay: "1",
                              wsjrdp_camt_transaction: {comment: "b"}}

      expect(response).to redirect_to(edit_wsjrdp_camt_transaction_path(returned, return_url: origin))
    end

    it "ignores a path that leads off the site" do
      patch :update, params: {id: returned.id, return_url: "https://example.org/x",
                              wsjrdp_camt_transaction: {comment: "c"}}

      expect(response).to redirect_to(wsjrdp_camt_transaction_path(returned))
    end

    it "ignores a protocol-relative path" do
      get :show, params: {id: returned.id, return_url: "//example.org/x"}

      expect(controller.send(:return_path)).to be_nil
    end
  end

  describe "PATCH #update" do
    def update(record, attrs, **params)
      patch :update, params: {id: record.id, wsjrdp_camt_transaction: attrs, **params}
    end

    it "saves and goes back to the reading page" do
      update(returned, {comment: "Neuer Kommentar", return_status: "paid",
                        subject: people(:yp_a_1).to_s, subject_id: people(:yp_a_1).id}, save: "1")

      expect(response).to redirect_to(wsjrdp_camt_transaction_path(returned))
      expect(returned.reload).to have_attributes(comment: "Neuer Kommentar", return_status: "paid",
        subject: people(:yp_a_1))
    end

    it "comes back to the edit page for Speichern und weiter bearbeiten" do
      update(returned, {comment: "Weiter"}, stay: "1")

      expect(response).to redirect_to(edit_wsjrdp_camt_transaction_path(returned))
      expect(returned.reload.comment).to eq("Weiter")
    end

    it "comes back to the row's detail from a frame" do
      request.headers["Turbo-Frame"] = "bkframe-acc-#{returned.id}"

      update(returned, {comment: "in der Zeile"}, stay: "1")

      expect(response).to redirect_to(wsjrdp_camt_transaction_path(returned))
      expect(returned.reload.comment).to eq("in der Zeile")
    end

    it "leaves the person alone when the request does not carry the field" do
      update(returned, {comment: "nur der Kommentar"})

      expect(returned.reload).to have_attributes(comment: "nur der Kommentar", subject: people(:yp_a_1))
    end

    it "links the person" do
      update(plain, {subject: people(:yp_a_1).to_s, subject_id: people(:yp_a_1).id})

      expect(plain.reload.subject).to eq(people(:yp_a_1))
    end

    it "unlinks the person on an emptied field" do
      update(returned, {subject: "", subject_id: people(:yp_a_1).id})

      expect(returned.reload.subject).to be_nil
    end

    # A save that fails its validation: the edit page again, the reasons as an
    # alert, nothing saved.
    describe "validation" do
      def refusal = assigns(:camt_transaction).errors.full_messages

      it "refuses a return status there is none of" do
        update(returned, {return_status: "bogus", comment: "x"})

        expect(response).to have_http_status(422)
        expect(refusal).to include("Retoure-Status ist kein gültiger Wert")
        expect(returned.reload).to have_attributes(return_status: "in_review", comment: "Testkommentar")
      end

      it "refuses a person that does not exist" do
        update(plain, {subject: "Niemand", subject_id: 0})

        expect(refusal).to include("Beteiligte Person wurde nicht gefunden")
        expect(plain.reload.subject_id).to be_nil
      end

      it "refuses a name that was typed but not chosen" do
        update(returned, {subject: "Erika Tippfehler", subject_id: ""})

        expect(refusal).to include("Beteiligte Person muss aus der Vorschlagsliste gewählt werden")
        expect(returned.reload.subject).to eq(people(:yp_a_1))
      end
    end
  end
end
