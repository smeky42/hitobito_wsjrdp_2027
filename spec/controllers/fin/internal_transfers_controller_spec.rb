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
  before_all(setup_fixtures: true) {}

  def giro_iban = InternalTransferSpecHelpers::GIRO_IBAN

  def savings_iban = InternalTransferSpecHelpers::SAVINGS_IBAN

  def day = Date.new(2026, 3, 2)

  let_it_be(:giro) { it_account("Giro", iban: InternalTransferSpecHelpers::GIRO_IBAN) }
  let_it_be(:savings) { it_account("Tagesgeld", iban: InternalTransferSpecHelpers::SAVINGS_IBAN) }

  let_it_be(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let_it_be(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }

  def pair_rows
    out = it_camt(giro, -1000, day, cdtr_iban: savings_iban)
    into = it_camt(savings, 1000, day, dbtr_iban: giro_iban)
    [out, into]
  end

  def key(record) = record.internal_transfer_leg_key

  def listed = controller.transfers.page.map(&:transfer)

  before { sign_in(finance) }

  describe "rendered" do
    render_views

    def doc = Nokogiri::HTML(response.body)

    # The box hands each pair over as "out>in", the key #link reads.
    it "offers a unique pair, a group of candidates and a row without counterpart" do
      out, into = pair_rows
      it_camt(giro, -500, day, cdtr_iban: savings_iban)
      it_camt(savings, 500, day, dbtr_iban: giro_iban)
      it_camt(savings, 500, day + 1, dbtr_iban: giro_iban)
      it_camt(giro, -700, Date.new(2026, 1, 5), cdtr_iban: savings_iban)

      get :index

      box = doc.at_css("#internal-transfer-suggestions")
      expect(box.at_css("input[name='pairs[]']")["value"]).to eq("#{key(out)}>#{key(into)}")
      expect(box.css("input[type=radio][name='choice[0]']").size).to eq(3)
      expect(box.css("input[name='legs[]']")).to be_present
    end

    it "shows the read tier the list, but neither suggestions nor 'Neue Umbuchung'" do
      pair_rows
      sign_in(reader)

      get :index

      expect(doc.at_css("#internal-transfer-suggestions")).to be_nil
      expect(response.body).not_to include(new_internal_transfer_path)
    end

    describe "a transfer" do
      let!(:transfer) { WsjrdpInternalTransfer.link!(pair_rows, meta: {"source" => "manual"}, comment: "Notiz") }

      def edit_link = doc.at_css("a[href='#{edit_internal_transfer_path(transfer)}']")

      it "shows the flow, the legs with their sum and links, editing in the page's frame" do
        get :show, params: {id: transfer.id}

        detail = doc.at_css(".it-detail")
        expect(detail.css(".it-card").map { |card| card.text.squish })
          .to match([include("Giro", "-1.000,00"), include("Tagesgeld", "1.000,00")])
        expect(detail.at_css("tfoot").text.squish).to include("0,00")
        transfer.camt_transactions.each do |row|
          expect(detail.at_css("a[href='#{wsjrdp_camt_transaction_path(row)}']")).to be_present
        end
        expect(edit_link["data-turbo-frame"]).to eq("bkframe-itpage-#{transfer.id}")
      end

      it "answers a row's frame with the detail alone, editing in that frame" do
        request.headers["Turbo-Frame"] = "bkframe-it-#{transfer.id}"

        get :show, params: {id: transfer.id}

        expect(doc.at_css("turbo-frame#bkframe-it-#{transfer.id} .it-detail")).to be_present
        expect(response.body).not_to include("<html")
        expect(edit_link["data-turbo-frame"]).to eq("bkframe-it-#{transfer.id}")
      end

      it "offers the read tier no Bearbeiten" do
        sign_in(reader)

        get :show, params: {id: transfer.id}

        expect(edit_link).to be_nil
      end

      # The side that lacks the open rest offers it as the picker's target.
      it "edits the legs with 'entfernen' and a transaction picker per side" do
        kept, dropped = transfer.camt_transactions.sort_by(&:signed_base_amount)
        dropped.update_columns(internal_transfer_id: nil)

        get :edit, params: {id: transfer.id}

        expect(doc.css("input[name='remove_legs[]']").pluck("value")).to eq([key(kept)])
        from, to = doc.css("[data-tp]")
        expect(from.to_h).to include("data-sign" => "out", "data-multi" => "0", "data-name" => "add_legs[]",
          "data-anchor" => "2026-03-02")
        expect(to.to_h).to include("data-sign" => "in", "data-multi" => "1", "data-target" => "1000.0")
        expect(from["data-target"]).to be_blank
        expect(from["data-exclude"].split(",")).to include(key(kept))
      end
    end
  end

  describe "GET index" do
    let_it_be(:pair) { WsjrdpInternalTransfer.link!(pair_rows) }
    let_it_be(:other) do
      WsjrdpInternalTransfer.link!([it_camt(savings, -7, day, cdtr_iban: giro_iban)], comment: "Zinsen Mai")
    end

    def index(filter) = get(:index, params: {f: filter})

    it "lists every transfer" do
      get :index

      expect(listed).to contain_exactly(pair, other)
    end

    it "shows only the open transfers with the quick filter 'offen'" do
      index("!(!(!(st,in,open)))")

      expect(listed).to eq([other])
    end

    it "filters by the Von account" do
      index("!(!(!(fra,in,#{savings.id})))")

      expect(listed).to eq([other])
    end

    it "filters by an account on either side" do
      index("!(!(!(acc,in,#{savings.id})))")

      expect(listed).to contain_exactly(pair, other)
    end

    it "filters by the amount" do
      index("!(!(!(amt,eq,7)))")

      expect(listed).to eq([other])
    end

    it "filters by a Von account a side does not have" do
      index("!(!(!(fra,not_in,#{savings.id})))")

      expect(listed).to eq([pair])
    end

    # A side without any account (the open transfer's Nach) has none of them.
    it "keeps a side without accounts under 'ist nicht'" do
      index("!(!(!(toa,not_in,#{savings.id})))")

      expect(listed).to eq([other])
    end

    it "filters by an account neither side has" do
      index("!(!(!(acc,not_in,#{giro.id})))")

      expect(listed).to eq([other])
    end

    it "finds a transfer by its comment in the full-text search" do
      index("!(!(!(q,ct,'zinsen')))")

      expect(listed).to eq([other])
    end
  end

  it "redirects the filter builder's apply back to the list" do
    post :apply, params: {tree: "[]"}

    expect(response).to redirect_to(%r{/fin/acc/internal_transfers})
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
    end

    it "marks a row as no transfer at all" do
      out = it_camt(giro, -700, Date.new(2026, 1, 5), cdtr_iban: savings_iban)
      post :dismiss, params: {legs: [key(out)]}

      expect(out.reload).to be_not_internal_transfer
    end
  end

  describe "editing" do
    let_it_be(:rows) { pair_rows }
    let_it_be(:transfer, refind: true) { WsjrdpInternalTransfer.link!(rows) }

    def update(**params) = patch(:update, params: {id: transfer.id, **params})

    it "saves comment and legs, back to the transfer's page" do
      extra = it_camt(savings, 3, day, dbtr_iban: giro_iban)
      update(wsjrdp_internal_transfer: {comment: "geändert"}, add_legs: [key(extra)], remove_legs: [key(rows.last)])

      expect(response).to redirect_to(internal_transfer_path(transfer, details: "open"))
      expect(transfer.reload.legs).to contain_exactly(rows.first, extra)
      expect(transfer.comment).to eq("geändert")
      expect(transfer.link_meta["edits"].last["by"]["person_id"]).to eq(finance.id)
    end

    describe "from a frame" do
      def redirect_top_url = Nokogiri::HTML(response.body).at_css("turbo-stream[action='redirect_top']")["url"]

      before { request.accept = "text/vnd.turbo-stream.html, text/html" }

      it "leaves a row's frame for the list with the row open" do
        request.headers["Turbo-Frame"] = "bkframe-it-#{transfer.id}"
        update(wsjrdp_internal_transfer: {comment: "x"})

        expect(redirect_top_url).to eq(internal_transfers_path(o: transfer.id))
      end

      it "leaves the page's frame for the transfer's page" do
        request.headers["Turbo-Frame"] = "bkframe-itpage-#{transfer.id}"
        update(wsjrdp_internal_transfer: {comment: "x"})

        expect(redirect_top_url).to eq(internal_transfer_path(transfer))
      end
    end

    it "dissolves the transfer when its last legs are removed" do
      update(wsjrdp_internal_transfer: {comment: ""}, remove_legs: rows.map { |row| key(row) })

      expect(response).to redirect_to(internal_transfers_path)
      expect(WsjrdpInternalTransfer.exists?(transfer.id)).to be(false)
      expect(flash[:notice]).to eq("Umbuchung #{transfer.id} aufgelöst.")
    end

    it "keeps the form with an error when an added row is taken by now" do
      taken = it_camt(savings, 3, day, dbtr_iban: giro_iban)
      WsjrdpInternalTransfer.link!([taken])
      update(add_legs: [key(taken)])

      expect(response).to have_http_status(422)
      expect(assigns(:transfer).errors[:base]).to be_present
      expect(transfer.reload.legs).to match_array(rows)
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
      expect(assigns(:transfer).errors[:base]).to be_present
      expect(WsjrdpInternalTransfer.count).to eq(0)
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
