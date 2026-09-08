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

  before { sign_in(person) }

  def doc = Nokogiri::HTML(response.body)

  # The OUTERMOST turbo frame of the response -- the one the detail view wraps
  # itself in. A detail may carry further frames below it (an embedded table's
  # rows), so the first in document order is the one under test.
  def outer_frame_id = doc.at_css("turbo-frame")&.[]("id")

  def frame_ids = doc.css("turbo-frame").pluck("id")

  # The row keys of the rendered list (the widget puts them into the lazy detail
  # frame's DOM id, under the list's own "bk" id prefix).
  def rendered_ids
    response.body.scan(/bkframe-bk-(\d+)/).flatten
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
  end
end
