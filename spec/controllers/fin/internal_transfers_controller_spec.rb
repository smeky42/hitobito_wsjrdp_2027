# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Umbuchungen (/fin/acc/internal_transfers): the suggestions box, the list,
# a transfer's detail and edit mode, and the import scripts' API. All names,
# IBANs and amounts are invented.
describe Fin::InternalTransfersController do
  render_views

  let(:giro_iban) { InternalTransferSpecHelpers::GIRO_IBAN }
  let(:savings_iban) { InternalTransferSpecHelpers::SAVINGS_IBAN }
  let!(:giro) { it_account("Giro", iban: giro_iban) }
  let!(:savings) { it_account("Tagesgeld", iban: savings_iban) }
  let(:day) { Date.new(2026, 3, 2) }

  let(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }

  def doc = Nokogiri::HTML(response.body)

  def pair_rows
    out = it_camt(giro, -1000, day, cdtr_iban: savings_iban)
    into = it_camt(savings, 1000, day, dbtr_iban: giro_iban)
    [out, into]
  end

  def key(record) = record.internal_transfer_leg_key

  before { sign_in(finance) }

  describe "GET index" do
    it "offers a unique pair in the suggestions box" do
      out, into = pair_rows
      get :index

      box = doc.at_css("#internal-transfer-suggestions")
      expect(box.text).to include("Eindeutig (1)", "Giro → Tagesgeld", "1.000,00")
      expect(box.at_css("input[name='pairs[]']")["value"]).to eq("#{key(out)}>#{key(into)}")
    end

    it "groups competing candidates with a choice and 'keine davon'" do
      it_camt(giro, -500, day, cdtr_iban: savings_iban)
      it_camt(savings, 500, day, dbtr_iban: giro_iban)
      it_camt(savings, 500, day + 1, dbtr_iban: giro_iban)
      get :index

      box = doc.at_css("#internal-transfer-suggestions")
      expect(box.text).to include("Mehrere Kandidaten (1)", "keine davon")
      expect(box.css("input[type=radio][name='choice[0]']").size).to eq(3)
    end

    it "shows a row without counterpart once its bank days are over" do
      it_camt(giro, -700, Date.new(2026, 1, 5), cdtr_iban: savings_iban)
      get :index

      expect(doc.at_css("#internal-transfer-suggestions").text)
        .to include("Ohne Gegenseite (1)", "Als offene Umbuchung anlegen", "Keine Umbuchung")
    end

    it "lists the transfers with their status and accounts" do
      transfer = WsjrdpInternalTransfer.link!(pair_rows)
      get :index

      row = doc.at_css("tr.exp-row")
      expect(row.text.squish).to include("02.03.2026", "Giro", "Tagesgeld", "vollständig", "1.000,00")
      expect(doc.css("turbo-frame[id^='bkframe-it-']").pluck("src"))
        .to include(internal_transfer_path(transfer, expandable_table_level: 1))
    end

    it "shows only the open transfers with the quick filter 'offen'" do
      WsjrdpInternalTransfer.link!(pair_rows)
      open_one = WsjrdpInternalTransfer.link!([it_camt(giro, -5, day, cdtr_iban: savings_iban)])
      get :index, params: {f: "!(!(!(st,in,open)))"}

      expect(doc.css("tr.exp-row").size).to eq(1)
      expect(doc.at_css("tr.exp-row").text).to include("offen")
      expect(open_one.status).to eq(:open)
      expect(doc.css(".flt-preset").map { |link| link.text.strip }).to include("vollständig", "offen")
    end

    it "filters by the accounts and the amount" do
      WsjrdpInternalTransfer.link!(pair_rows)
      other = WsjrdpInternalTransfer.link!([it_camt(savings, -7, day, cdtr_iban: giro_iban)])

      get :index, params: {f: "!(!(!(fra,in,#{savings.id})))"}
      expect(doc.css("tr.exp-row").size).to eq(1)
      expect(other.from_accounts).to eq([savings])

      get :index, params: {f: "!(!(!(acc,in,#{savings.id})))"}
      expect(doc.css("tr.exp-row").size).to eq(2)

      get :index, params: {f: "!(!(!(amt,eq,7)))"}
      expect(doc.css("tr.exp-row").size).to eq(1)
    end

    # "ist nicht": no account of the side is the chosen one -- a side without
    # any account (the open transfer's Nach) included.
    it "filters by an account a side does not have" do
      WsjrdpInternalTransfer.link!(pair_rows)
      other = WsjrdpInternalTransfer.link!([it_camt(savings, -7, day, cdtr_iban: giro_iban)])

      get :index, params: {f: "!(!(!(fra,not_in,#{savings.id})))"}
      expect(doc.css("tr.exp-row").map { |tr| tr.text.squish }).to match([include("1.000,00")])

      get :index, params: {f: "!(!(!(toa,not_in,#{savings.id})))"}
      expect(doc.css("tr.exp-row").size).to eq(1)
      expect(other.to_accounts).to be_empty

      # The pair has the Giro on its Von side; the open one none at all.
      get :index, params: {f: "!(!(!(acc,not_in,#{giro.id})))"}
      expect(doc.css("tr.exp-row").map { |tr| tr.text.squish }).to match([include("7,00")])
    end

    it "finds a transfer by its comment or a purpose in the full-text search" do
      WsjrdpInternalTransfer.link!(pair_rows)
      WsjrdpInternalTransfer.link!([it_camt(savings, -7, day, cdtr_iban: giro_iban)], comment: "Zinsen Mai")

      get :index, params: {f: "!(!(!(q,ct,'zinsen')))"}
      expect(doc.css("tr.exp-row").size).to eq(1)

      get :index, params: {f: "!(!(!(q,ct,'zzz-nirgends')))"}
      expect(doc.css("tr.exp-row").size).to eq(0)
    end

    it "redirects the filter builder's apply back to the list" do
      post :apply, params: {tree: "[]"}
      expect(response).to redirect_to(%r{/fin/acc/internal_transfers})
    end

    it "shows the read tier the list, but neither suggestions nor 'Neue Umbuchung'" do
      pair_rows
      sign_in(reader)
      get :index

      expect(response).to be_successful
      expect(doc.at_css("#internal-transfer-suggestions")).to be_nil
      expect(response.body).not_to include("Neue Umbuchung")
    end
  end

  describe "POST link" do
    it "links the checked unique pairs" do
      out, into = pair_rows
      post :link, params: {pairs: ["#{key(out)}>#{key(into)}"]}

      expect(response).to redirect_to(internal_transfers_path)
      transfer = WsjrdpInternalTransfer.last
      expect(transfer.legs).to contain_exactly(out, into)
      expect(transfer.link_meta).to include("source" => "suggestion", "rule" => "both_ibans")
      expect(transfer.link_meta.dig("by", "person_id")).to eq(finance.id)
    end

    it "links the pair picked in a group and ignores 'keine davon'" do
      out, into = pair_rows
      post :link, params: {choice: {"0" => "#{key(out)}>#{key(into)}", "1" => "none"}}

      expect(WsjrdpInternalTransfer.count).to eq(1)
    end

    it "skips a pair whose rows are taken by now" do
      out, into = pair_rows
      WsjrdpInternalTransfer.link!([out])

      expect { post :link, params: {pairs: ["#{key(out)}>#{key(into)}"]} }
        .not_to change(WsjrdpInternalTransfer, :count)
      expect(flash[:notice]).to eq("0 Umbuchungen verknüpft.")
    end

    it "is closed to the read tier" do
      sign_in(reader)
      expect { post :link, params: {pairs: []} }.to raise_error(CanCan::AccessDenied)
    end
  end

  describe "POST dismiss" do
    it "lets each row of a dismissed pair deny the other" do
      out, into = pair_rows
      post :dismiss, params: {pairs: ["#{key(out)}>#{key(into)}"]}

      expect(out.reload.denied_internal_transfer_candidates).to eq([key(into)])
      expect(into.reload.denied_internal_transfer_candidates).to eq([key(out)])
      expect(Fin::InternalTransferDetection.new.pairs).to be_empty
    end

    it "marks a row as no transfer at all" do
      out = it_camt(giro, -700, Date.new(2026, 1, 5), cdtr_iban: savings_iban)
      post :dismiss, params: {legs: [key(out)]}

      expect(out.reload).to be_not_internal_transfer
      expect(Fin::InternalTransferDetection.new.missing).to be_empty
    end
  end

  describe "GET show" do
    let!(:transfer) { WsjrdpInternalTransfer.link!(pair_rows, meta: {"source" => "manual"}, comment: "Notiz") }

    it "shows the flow, the legs with their sum and the link" do
      get :show, params: {id: transfer.id}

      detail = doc.at_css(".it-detail")
      expect(detail.css(".it-card").map { |card| card.text.squish })
        .to match([include("Von", "Giro", "-1.000,00"), include("Nach", "Tagesgeld", "1.000,00")])
      expect(detail.at_css(".it-flow-arrow").text.squish).to include("1.000,00", "am selben Tag")
      expect(detail.at_css("tfoot").text.squish).to include("Summe", "0,00")
      # The legs are an expandable table: a row opens the bank transaction's
      # fields, the double button leads to its page.
      expect(detail.css(".bk-item-detail").map { |item| item.text.squish })
        .to match_array([include("Empfänger", "Verwendungszweck"), include("Auftraggeber", "Verwendungszweck")])
      transfer.camt_transactions.each do |row|
        expect(detail.at_css("a[href='#{wsjrdp_camt_transaction_path(row)}']")).to be_present
      end
      expect(detail.at_css(".it-meta").text).to include("von Hand angelegt", "Notiz")
      expect(detail.at_css("a[href='#{edit_internal_transfer_path(transfer)}']")["data-turbo-frame"])
        .to eq("bkframe-itpage-#{transfer.id}")
    end

    it "answers a row's frame with the detail alone" do
      request.headers["Turbo-Frame"] = "bkframe-it-#{transfer.id}"
      get :show, params: {id: transfer.id}

      frame = doc.at_css("turbo-frame#bkframe-it-#{transfer.id}")
      expect(frame.at_css(".it-detail")).to be_present
      expect(frame.at_css("a[href='#{edit_internal_transfer_path(transfer)}']")["data-turbo-frame"])
        .to eq("bkframe-it-#{transfer.id}")
    end

    it "offers the read tier no Bearbeiten" do
      sign_in(reader)
      get :show, params: {id: transfer.id}

      expect(response).to be_successful
      expect(doc.at_css("a[href='#{edit_internal_transfer_path(transfer)}']")).to be_nil
    end
  end

  describe "editing" do
    let!(:rows) { pair_rows }
    let!(:transfer) { WsjrdpInternalTransfer.link!(rows) }

    it "shows the legs with 'entfernen' and a transaction picker per side" do
      get :edit, params: {id: transfer.id}

      expect(doc.css("input[name='remove_legs[]']").pluck("value")).to contain_exactly(*rows.map { |row| key(row) })
      from, to = doc.css("[data-tp]")
      expect(from.to_h).to include("data-sign" => "out", "data-multi" => "0", "data-name" => "add_legs[]",
        "data-anchor" => "2026-03-02")
      expect(to.to_h).to include("data-sign" => "in", "data-multi" => "1")
      expect(from["data-exclude"].split(",")).to contain_exactly(*rows.map { |row| key(row) })
    end

    it "offers the open rest as 'gleicht aus' on the side that lacks it" do
      rows.last.update_columns(internal_transfer_id: nil)
      get :edit, params: {id: transfer.id}

      from, to = doc.css("[data-tp]")
      expect(to["data-target"]).to eq("1000.0")
      expect(from["data-target"]).to be_blank
      expect(to.at_css("[data-tp-balances]").text).to include("1.000,00")
    end

    it "saves comment and legs, back to the transfer's page" do
      extra = it_camt(savings, 3, day, dbtr_iban: giro_iban)
      patch :update, params: {id: transfer.id, wsjrdp_internal_transfer: {comment: "geändert"},
                              add_legs: [key(extra)], remove_legs: [key(rows.last)]}

      expect(response).to redirect_to(internal_transfer_path(transfer, details: "open"))
      expect(transfer.reload.legs).to contain_exactly(rows.first, extra)
      expect(transfer.comment).to eq("geändert")
      expect(transfer.link_meta["edits"].last["by"]["person_id"]).to eq(finance.id)
    end

    it "leaves a row's frame for the list with the row open" do
      request.headers["Turbo-Frame"] = "bkframe-it-#{transfer.id}"
      request.accept = "text/vnd.turbo-stream.html, text/html"
      patch :update, params: {id: transfer.id, wsjrdp_internal_transfer: {comment: "x"}}

      expect(doc.at_css("turbo-stream[action='redirect_top']")["url"]).to eq(internal_transfers_path(o: transfer.id))
    end

    it "leaves the page's frame for the transfer's page" do
      request.headers["Turbo-Frame"] = "bkframe-itpage-#{transfer.id}"
      request.accept = "text/vnd.turbo-stream.html, text/html"
      patch :update, params: {id: transfer.id, wsjrdp_internal_transfer: {comment: "x"}}

      expect(doc.at_css("turbo-stream[action='redirect_top']")["url"]).to eq(internal_transfer_path(transfer))
    end

    it "dissolves the transfer when its last legs are removed" do
      patch :update, params: {id: transfer.id, wsjrdp_internal_transfer: {comment: ""},
                              remove_legs: rows.map { |row| key(row) }}

      expect(response).to redirect_to(internal_transfers_path)
      expect(WsjrdpInternalTransfer.exists?(transfer.id)).to be(false)
      expect(flash[:notice]).to eq("Umbuchung #{transfer.id} aufgelöst.")
    end

    it "keeps the form with an error when an added row is taken by now" do
      taken = it_camt(savings, 3, day, dbtr_iban: giro_iban)
      WsjrdpInternalTransfer.link!([taken])
      patch :update, params: {id: transfer.id, add_legs: [key(taken)]}

      expect(response).to have_http_status(422)
      expect(response.body).to include("gehört inzwischen zu einer anderen Umbuchung")
    end

    it "destroys a transfer and keeps its rows" do
      delete :destroy, params: {id: transfer.id}

      expect(response).to redirect_to(internal_transfers_path)
      expect(rows.map { |row| row.reload.internal_transfer_id }).to all(be_nil)
    end

    it "is closed to the read tier" do
      sign_in(reader)
      expect { get :edit, params: {id: transfer.id} }.to raise_error(CanCan::AccessDenied)
      expect { delete :destroy, params: {id: transfer.id} }.to raise_error(CanCan::AccessDenied)
    end
  end

  describe "a new transfer" do
    it "creates a transfer of the ticked rows, also one-sided" do
      out = it_camt(giro, -9, day, cdtr_iban: savings_iban)
      post :create, params: {add_legs: [key(out)], wsjrdp_internal_transfer: {comment: "von Hand"}}

      transfer = WsjrdpInternalTransfer.last
      expect(response).to redirect_to(internal_transfer_path(transfer, details: "open"))
      expect(transfer.legs).to eq([out])
      expect(transfer.status).to eq(:open)
      expect(transfer.link_meta["source"]).to eq("manual")
    end

    it "asks for at least one row" do
      post :create, params: {wsjrdp_internal_transfer: {comment: "leer"}}

      expect(response).to have_http_status(422)
      expect(response.body).to include("mindestens eine Buchung")
    end
  end

  describe "POST link_unique (the import scripts' API)" do
    let(:token) do
      ServiceToken.create!(layer: groups(:root), name: "Import", permission: "layer_and_below_read",
        scopes: %w[finance:read finance:write], acting_person: finance)
    end

    before { sign_out(finance) }

    it "links every unique pair for a service token and reports the rest" do
      out, into = pair_rows
      request.headers["X-Token"] = token.plain_token
      post :link_unique, format: :json

      expect(response).to be_successful
      expect(response.parsed_body).to eq("linked" => 1, "ambiguous" => 0, "waiting" => 0, "without_counterpart" => 0)
      expect(WsjrdpInternalTransfer.last.legs).to contain_exactly(out, into)
      expect(WsjrdpInternalTransfer.last.link_meta).to include("source" => "api")
      expect(WsjrdpInternalTransfer.last.link_meta.dig("by", "service_token_id")).to eq(token.id)
    end

    it "refuses a token that may only read" do
      reading = ServiceToken.create!(layer: groups(:root), name: "Lesen", permission: "layer_and_below_read",
        scopes: %w[finance:read], acting_person: finance)
      request.headers["X-Token"] = reading.plain_token
      pair_rows

      post :link_unique, format: :json

      expect(response).to have_http_status(:forbidden)
      expect(WsjrdpInternalTransfer.count).to eq(0)
    end

    it "is not reached by a signed-in person" do
      sign_in(finance)
      pair_rows
      post :link_unique, format: :json

      expect(response).to have_http_status(:forbidden)
      expect(WsjrdpInternalTransfer.count).to eq(0)
    end
  end
end
