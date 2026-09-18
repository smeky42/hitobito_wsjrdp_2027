# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Buchungen page and one booking's detail. The detail doubles as the pane an
# expandable table lazy-loads into its open row, and it is reached from TWO
# tables with different prefixes:
#
#   * the Buchungen list itself (BOOKINGS_POLICY prefix "", DOM id prefix "bk")
#     asks as "bkframe-bk-<id>",
#   * the condensed bookings table embedded in a Buchhaltung item detail
#     (Fin::BookkeepingSummaries.item_bookings_policy_options, prefix "b") asks
#     as "bkframe-b-<id>".
#
# Which is why the frame id in the RESPONSE is what these examples assert: a
# view that hardcodes one of the two answers the wrong frame for the other host,
# and Turbo shows "Content missing" instead of the detail.
describe Fin::BookingsController do
  render_views

  let(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  # Invented header coordinates; the batch only has to exist so the detail's
  # Verknüpfungen block has a Buchungsstapel to link to.
  let!(:batch) do
    DatevBookingBatch.create!(consultant_number: "1", client_number: "2",
      label: "Teststapel", period_from: Date.new(2026, 1, 1),
      period_to: Date.new(2026, 1, 31), financial_year_start: Date.new(2026, 1, 1),
      primanota_number: "01-2026/0001", import_export: "import")
  end

  # The Konto is a BANK account, so signed_base_amount is +amount for "D" and
  # -amount for "C" (no income/expense sign flip, see
  # doc/fin/money_conventions.md).
  def create_booking(posting_text, amount, debit_credit = "D")
    DatevBooking.create!(batch: batch, buchungs_guid: SecureRandom.uuid,
      account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
      cost_center_number: "K100",
      base_amount: amount, transaction_amount: amount, debit_credit: debit_credit,
      base_currency: "EUR", booking_date: Date.new(2026, 2, 1),
      posting_text: posting_text)
  end

  let!(:booking) { create_booking("Testbuchung Alpha", 100) }
  let!(:other_booking) { create_booking("Testbuchung Beta", 70, "C") }

  # The read tier reaches the reading page and nothing beyond it.
  let(:extern) { Group::Extern.create!(name: "Extern", parent: groups(:root)) }
  let(:auditor) { Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: extern).person }

  before { sign_in(person) }

  def doc = Nokogiri::HTML(response.body)

  # The OUTERMOST turbo frame of the response -- the one the detail view wraps
  # itself in. A detail may carry further frames below it (an embedded table's
  # rows), so the first in document order is the one under test.
  def outer_frame_id = doc.at_css("turbo-frame")&.[]("id")

  def frame_ids = doc.css("turbo-frame").pluck("id")

  # The field labels of the rendered detail, in document order.
  def detail_labels = doc.css("dt").map { |dt| dt.text.strip }

  # The dd of the row with this label, and its text.
  def detail_cell(label)
    index = detail_labels.index(label)
    index && doc.css("dd")[index]
  end

  def detail_value(label) = detail_cell(label)&.text&.squish

  # The inputs of the detail's own form, by name; the layout's quicksearch is a
  # GET form of its own and never carries these.
  def input_names = doc.css("input, select, textarea").pluck("name").compact

  # The row keys of the rendered list (the widget puts them into the lazy detail
  # frame's DOM id, under the list's own "bk" id prefix).
  def rendered_ids
    response.body.scan(/bkframe-bk-(\d+)/).flatten
  end

  # The table's summary line, as the widget's toolbar renders it. .strip, not
  # .squish: squish would fold the money format's NBSP away.
  def summary_line
    doc.css("div.text-muted.small").map { |node| node.text.strip }
      .find { |text| text.include?("Summe (gefiltert)") }
  end

  describe "GET index" do
    it "lists the bookings, newest first, each with its lazy detail frame" do
      get :index
      expect(response).to be_successful
      expect(rendered_ids).to match_array([booking.id.to_s, other_booking.id.to_s])
      expect(response.body).to include("Testbuchung Alpha").and include("Testbuchung Beta")
    end
  end

  describe "GET show" do
    let(:canonical) { "bkframe-bk-#{booking.id}" }

    it "renders the full detail page, its frame wrapped in #main" do
      get :show, params: {id: booking.id}

      expect(response).to be_successful
      expect(response.body).to include("<html")
      expect(response.body).to include(%(<turbo-frame id="#{canonical}"))
      expect(outer_frame_id).to eq(canonical)
      expect(doc.at_css("turbo-frame##{canonical}").parent["id"]).to eq("main")
      expect(response.body).to include("Testbuchung Alpha")
    end

    # Lazily loaded out of the Buchungen list: the frame it named comes back,
    # and nothing else -- no layout around it.
    it "answers the Buchungen list's frame without a layout" do
      request.headers["Turbo-Frame"] = "bkframe-bk-#{booking.id}"
      get :show, params: {id: booking.id, expandable_table_level: "1"}

      expect(response).to be_successful
      expect(response.body).to include(%(<turbo-frame id="bkframe-bk-#{booking.id}"))
      expect(frame_ids).to eq(["bkframe-bk-#{booking.id}"])
      expect(response.body).not_to include("<html")
      expect(response.body).to include("Testbuchung Alpha")
    end

    # THE regression: the same detail lazy-loaded out of the condensed bookings
    # table embedded in a Buchhaltung item detail (prefix "b"). A hardcoded
    # "bkframe-bk-<id>" answered the wrong frame here and Turbo rendered
    # "Content missing".
    it "answers the embedded bookings table's frame under the 'b' prefix" do
      request.headers["Turbo-Frame"] = "bkframe-b-#{booking.id}"
      get :show, params: {id: booking.id, expandable_table_level: "2"}

      expect(response).to be_successful
      expect(response.body).to include(%(<turbo-frame id="bkframe-b-#{booking.id}"))
      expect(frame_ids).to eq(["bkframe-b-#{booking.id}"])
      expect(response.body).not_to include("<html")
      expect(response.body).to include("Testbuchung Alpha")
    end

    # A header is only honoured when it names a detail frame of THIS record. A
    # stray one -- e.g. the redirect of a form submitted inside another row's
    # pane -- falls back to the canonical id, so Turbo never finds two nodes
    # carrying the other row's frame id.
    it "falls back to the canonical id for a header naming another booking" do
      request.headers["Turbo-Frame"] = "bkframe-bk-#{other_booking.id}"
      get :show, params: {id: booking.id}

      expect(response).to be_successful
      expect(frame_ids).to eq([canonical])
    end

    # The Betrag carries the booking's Soll/Haben written out, and set apart
    # from the figure by a margin rather than glued to it.
    it "writes the Soll/Haben of the Betrag out" do
      get :show, params: {id: booking.id}

      betrag = detail_cell("Betrag")
      expect(betrag.text).to include("100,00#{Fin::MoneyHelper::NBSP}€")
      expect(betrag.at_css("span.ms-3").text).to eq("Soll")

      get :show, params: {id: other_booking.id}
      expect(detail_cell("Betrag").at_css("span.ms-3").text).to eq("Haben")
    end

    # The second currency axis is a SPECIAL CASE now: on an EUR booking it would
    # only repeat the Betrag, so it stays away entirely.
    it "shows the original amount of a foreign-currency booking, without Soll/Haben" do
      booking.update!(base_amount: 230, transaction_amount: 1000, transaction_currency: "PLN",
        exchange_rate: 4.3478)
      get :show, params: {id: booking.id}

      expect(detail_cell("Betrag").at_css("span.ms-3").text).to eq("Soll")
      original = detail_cell("Original-Betrag")
      # .strip, not .squish: squish would fold the money format's NBSP away.
      expect(original.text.strip).to eq("1.000,00#{Fin::MoneyHelper::NBSP}zł")
      # The original amount states no Soll/Haben of its own, and carries its
      # currency itself -- there is no row for that either.
      expect(original.at_css("span.ms-3")).to be_nil
      expect(detail_labels).not_to include("Original-Währung")
    end

    it "shows no original amount on an EUR booking" do
      get :show, params: {id: booking.id}

      expect(detail_labels).to include("Betrag")
      expect(detail_labels).not_to include("Original-Betrag", "Original-Währung")
    end

    # The rate between the two amounts, right behind them and under the same
    # rule: it says something only where the currencies differ.
    it "shows the exchange rate of a foreign-currency booking" do
      booking.update!(base_amount: 230, transaction_amount: 1000, transaction_currency: "PLN",
        exchange_rate: 4.3478)
      get :show, params: {id: booking.id}

      expect(detail_value("Wechselkurs")).to eq("4,3478")
      expect(detail_labels.index("Wechselkurs"))
        .to eq(detail_labels.index("Original-Betrag") + 1)
    end

    it "shows no exchange rate on an EUR booking" do
      booking.update!(exchange_rate: 4.3478)
      get :show, params: {id: booking.id}

      expect(detail_labels).not_to include("Wechselkurs")
    end

    # The reading page reads: the editable fields carry no input, and an unset
    # one is not worth a row of its own.
    it "carries no input and hides the fields that are unset" do
      get :show, params: {id: booking.id}

      expect(input_names).not_to include("datev_booking[comment]",
        "datev_booking[user_comment]", "datev_booking[secondary_cost_center_number]")
      expect(detail_labels).not_to include("Sekundäre Kostenstelle",
        "Unter-Kostenstelle", "Kommentar", "Notizen")
      # Unit-Budget is the one editable field that is never unset: its value is
      # resolved, so its row stands here like any reading field.
      expect(detail_labels).to include("Unit-Budget?")
    end

    it "keeps a set field on the reading page" do
      booking.update!(user_comment: "für alle")
      get :show, params: {id: booking.id}

      # The help line follows the value in the same cell.
      expect(detail_value("Notizen")).to start_with("für alle")
    end

    # The Notizen stand right under the description, in its group, with their
    # help line. The write tier holds :log, so the helpdesk's ticket keys in
    # them are links here (a unit leader reads them as text:
    # spec/controllers/group/bookings_controller_spec.rb).
    it "places the notes after the description and links their tickets" do
      booking.update!(user_comment: "siehe FIN-123 und https://example.org/x")
      get :show, params: {id: booking.id}

      expect(detail_labels.index("Notizen")).to eq(detail_labels.index("Beschreibung") + 1)
      links = detail_cell("Notizen").css("a").to_h { |a| [a.text, a["href"]] }
      expect(links).to eq("FIN-123" => "https://helpdesk.worldscoutjamboree.de/browse/FIN-123",
        "https://example.org/x" => "https://example.org/x")
      expect(detail_value("Notizen")).to include("Deine permanenten Notizen")
    end

    # The /fin list is a page of its own, so this detail keeps its back link --
    # unlike a booking on a group's route, which hangs under the tab it would
    # lead back to (doc/fin/detail_partials.md §9).
    it "leads back to the list" do
      get :show, params: {id: booking.id}

      back = doc.css("a").find { |a| a.text.strip == "Zurück zur Liste" }
      expect(back["href"]).to eq(bookings_path)
    end

    it "offers the write tier the way to the edit page" do
      get :show, params: {id: booking.id}

      button = doc.css("a").find { |a| a.text.strip == "Bearbeiten" }
      expect(button["href"]).to eq(edit_booking_path(booking))
      expect(button["class"]).to include("btn-outline-primary")
    end

    it "offers the read tier none" do
      sign_in(auditor)
      get :show, params: {id: booking.id}

      expect(response).to be_successful
      expect(doc.css("a").map { |a| a.text.strip }).not_to include("Bearbeiten")
    end

    # The pane inside an open table row is untouched by the page's split: it
    # still turns into inputs where it stands.
    it "keeps the inline toggle in the lazy pane" do
      request.headers["Turbo-Frame"] = "bkframe-bk-#{booking.id}"
      get :show, params: {id: booking.id, expandable_table_level: "1"}

      expect(doc.at_css(".fin-edit-toggle").text).to include("Bearbeiten")
      expect(input_names).to include("datev_booking[comment]", "datev_booking[user_comment]")
    end
  end

  describe "GET edit" do
    it "renders the inputs of every editable field" do
      get :edit, params: {id: booking.id}

      expect(response).to be_successful
      expect(input_names).to include("datev_booking[secondary_cost_center_number]",
        "datev_booking[is_unit_budget]", "datev_booking[sub_cost_center_number]",
        "datev_booking[comment]", "datev_booking[user_comment]")
    end

    # The blank rule of the reading page is turned around here: a field with an
    # input has to stand, or there would be no way to fill it in.
    it "shows the editable fields although they are unset" do
      get :edit, params: {id: booking.id}

      expect(detail_labels).to include("Sekundäre Kostenstelle", "Unter-Kostenstelle",
        "Kommentar", "Notizen")
    end

    it "carries both submits and the way back" do
      get :edit, params: {id: booking.id}

      buttons = doc.css("button[type=submit]").to_h { |b| [b.text.strip, b["name"]] }
      expect(buttons).to include("Speichern" => "save",
        "Speichern und weiter bearbeiten" => "stay")
      cancel = doc.css("a").find { |a| a.text.strip == "Abbrechen" }
      expect(cancel["href"]).to eq(booking_path(booking))
    end

    it "offers the number of a new sub cost center next to the select" do
      get :edit, params: {id: booking.id}

      expect(input_names).to include("datev_booking[new_sub_cost_center_number]")
    end

    it "refuses the read tier" do
      sign_in(auditor)

      expect { get :edit, params: {id: booking.id} }.to raise_error(CanCan::AccessDenied)
    end
  end

  # Whether a booking belongs to a unit's budget: the booking's own flag, else
  # its two accounts combined, else the default -- and WHERE that answer came
  # from, which is what the column's suffix and the detail's parentheses say.
  # 1200 says yes, 66500 says no, so an untouched booking of this spec reads
  # "nein, Gegenkonto 66500".
  describe "Unit-Budget" do
    let!(:bank) { WsjrdpLedgerAccount.create!(number: "1200", name: "Testbank") }
    let!(:expense) do
      WsjrdpLedgerAccount.create!(number: "66500", name: "Testaufwand", is_unit_budget: false)
    end

    # One cell of the rendered table body, per row, as its inner markup.
    def cells(key)
      body = response.body[%r{<tbody[^>]*>.*</tbody>}m].to_s
      body.scan(/colkey='#{key}'>(.*?)<\/td>/m).flatten
    end

    def cell_texts(key) = cells(key).map { |cell| cell.gsub(/<[^>]+>/, " ").squish }

    it "is offered as a column, not shown by default" do
      get :index

      expect(Fin::DatevBookingsColumns.default_keys).not_to include("unit_budget")
      expect(response.body).to include("Unit-Budget?")
      expect(cells("unit_budget")).to be_empty
    end

    it "shows the answer with its source once the column is picked" do
      booking.update!(is_unit_budget: true)

      get :index, params: {c: "bdt,ub"}

      expect(cell_texts("unit_budget"))
        .to match_array(["ja Buchung", "nein Gegenkonto 66500"])
    end

    it "sorts the list by the resolved answer" do
      booking.update!(is_unit_budget: true)

      get :index, params: {c: "bdt,ub", s: "ub"}

      expect(response).to be_successful
      expect(rendered_ids).to eq([other_booking.id.to_s, booking.id.to_s])
    end

    it "writes the answer and its origin out on the reading page" do
      get :show, params: {id: booking.id}

      expect(detail_value("Unit-Budget?")).to eq("nein (automatisch, Gegenkonto 66500)")
    end

    # Two accounts that simply agree are the ordinary case and name no source:
    # the detail stops at "automatisch".
    it "names no source where both accounts agree" do
      booking.update!(offsetting_account_number: "1200", offsetting_account_kind: "BANK")

      get :show, params: {id: booking.id}

      expect(detail_value("Unit-Budget?")).to eq("ja (automatisch)")
    end

    # The same in the cell: the answer alone, without a muted source behind it.
    it "shows the bare answer in the cell where both accounts agree" do
      booking.update!(offsetting_account_number: "1200", offsetting_account_kind: "BANK")

      get :index, params: {c: "bdt,ub"}

      expect(cell_texts("unit_budget")).to include("ja")
      expect(cell_texts("unit_budget")).not_to include(a_string_matching(/ja Konten/))
    end

    it "names the booking itself where it carries the flag" do
      booking.update!(is_unit_budget: true)

      get :show, params: {id: booking.id}

      expect(detail_value("Unit-Budget?")).to eq("ja (Buchung)")
    end

    # The first option leaves the booking's own flag unset, so it names the
    # answer the accounts give -- here 66500's no.
    it "names the automatic answer in the edit select" do
      get :edit, params: {id: booking.id}

      options = doc.css("select[name='datev_booking[is_unit_budget]'] option")
        .map { |option| [option.text.strip, option["value"]] }
      expect(options).to eq([["automatisch (nein)", ""], ["ja", "true"], ["nein", "false"]])
    end

    # The summary's third figure: how much of the sum beside it counts against a
    # unit's budget. Both come from the SAME filtered relation, so the share can
    # never be read off another set -- here 1200/66500 make an untouched booking
    # a "nein", and only the one carrying the flag counts.
    it "states the Unit-Budget share of the sum" do
      booking.update!(is_unit_budget: true)

      get :index

      nbsp = Fin::MoneyHelper::NBSP
      expect(summary_line).to eq("2 Buchungen · Summe (gefiltert): 30,00#{nbsp}€ · " \
        "davon Unit-Budget: 100,00#{nbsp}€ (1 Buchungen)")
    end

    # Filtered, both figures follow: the share is computed over what is left,
    # not over the whole table.
    it "computes the share over the filtered rows only" do
      booking.update!(is_unit_budget: true)

      get :index, params: {f: "!(!(!(q,ct,Beta)))"}

      nbsp = Fin::MoneyHelper::NBSP
      expect(summary_line).to eq("1 Buchungen · Summe (gefiltert): -70,00#{nbsp}€ · " \
        "davon Unit-Budget: 0,00#{nbsp}€ (0 Buchungen)")
    end

    it "stores the override and clears it again" do
      patch :update, params: {id: booking.id, datev_booking: {is_unit_budget: "true"}}
      expect(booking.reload.is_unit_budget).to be true

      patch :update, params: {id: booking.id, datev_booking: {is_unit_budget: ""}}
      expect(booking.reload.is_unit_budget).to be_nil
      expect(booking.unit_budget).to eq([false, "gegenkonto"])
    end
  end

  describe "PATCH update" do
    it "stores both comments" do
      patch :update, params: {id: booking.id,
                              datev_booking: {comment: "intern", user_comment: "für alle"}}

      expect(booking.reload.comment).to eq("intern")
      expect(booking.user_comment).to eq("für alle")
    end

    # The columns are NOT NULL with "" as their default: an emptied comment is
    # stored as "", never as NULL.
    it "clears a comment to the empty string" do
      booking.update!(user_comment: "für alle")

      patch :update, params: {id: booking.id, datev_booking: {user_comment: ""}}

      expect(booking.reload.user_comment).to eq("")
    end

    # Which of the edit page's two submits was pressed is the whole difference:
    # `stay` comes back to go on editing, `save` goes on to the reading page.
    it "comes back to the edit page for Speichern und weiter bearbeiten" do
      patch :update, params: {id: booking.id, stay: "1",
                              datev_booking: {user_comment: "für alle"}}

      expect(response).to redirect_to(edit_booking_path(booking))
      expect(booking.reload.user_comment).to eq("für alle")
    end

    it "goes on to the reading page for Speichern" do
      patch :update, params: {id: booking.id, save: "1",
                              datev_booking: {user_comment: "für alle"}}

      expect(response).to redirect_to(booking_path(booking))
    end

    describe "a new sub cost center" do
      it "creates it under the booking's own cost center and assigns it" do
        expect do
          patch :update, params: {id: booking.id,
                                  datev_booking: {sub_cost_center_number: "",
                                                  new_sub_cost_center_number: " X9 "}}
        end.to change(WsjrdpSubCostCenter, :count).by(1)

        created = WsjrdpSubCostCenter.find_by(cost_center_number: "K100", number: "X9")
        expect(created).to be_present
        expect(created.name).to be_blank
        expect(booking.reload.sub_cost_center_number).to eq("X9")
      end

      # The number is unique within its cost center only, so an existing one is
      # reused rather than duplicated.
      it "reuses a number that already exists there" do
        WsjrdpSubCostCenter.create!(cost_center_number: "K100", number: "X9", name: "Teil X")

        expect do
          patch :update, params: {id: booking.id,
                                  datev_booking: {new_sub_cost_center_number: "X9"}}
        end.not_to change(WsjrdpSubCostCenter, :count)

        expect(booking.reload.sub_cost_center_number).to eq("X9")
      end

      # It wins over the select: that one cannot offer a number that does not
      # exist yet.
      it "beats the select" do
        WsjrdpSubCostCenter.create!(cost_center_number: "K100", number: "X1", name: "Teil X")

        patch :update, params: {id: booking.id,
                                datev_booking: {sub_cost_center_number: "X1",
                                                new_sub_cost_center_number: "X9"}}

        expect(booking.reload.sub_cost_center_number).to eq("X9")
      end

      it "writes nothing for a booking without a cost center" do
        booking.update!(cost_center_number: nil)

        expect do
          patch :update, params: {id: booking.id,
                                  datev_booking: {user_comment: "für alle",
                                                  new_sub_cost_center_number: "X9"}}
        end.not_to change(WsjrdpSubCostCenter, :count)

        expect(flash[:alert]).to include("keine Kostenstelle")
        expect(booking.reload.user_comment).to eq("")
        expect(booking.sub_cost_center_number).to be_nil
      end

      # The field stands on every save of the edit page; left empty it is not a
      # request for anything, and the select decides as before.
      it "is ignored when it is left empty" do
        WsjrdpSubCostCenter.create!(cost_center_number: "K100", number: "X1", name: "Teil X")

        expect do
          patch :update, params: {id: booking.id,
                                  datev_booking: {sub_cost_center_number: "X1",
                                                  new_sub_cost_center_number: ""}}
        end.not_to change(WsjrdpSubCostCenter, :count)

        expect(booking.reload.sub_cost_center_number).to eq("X1")
      end
    end
  end
end
