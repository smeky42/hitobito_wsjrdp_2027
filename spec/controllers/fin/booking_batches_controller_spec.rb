# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Buchungsstapel (DATEV booking batch / Primanota) list and one batch's
# detail. The detail doubles as the pane the list lazy-loads into its open row
# (SUMMARY_POLICY prefix "", DOM id prefix "batch" -> "bkframe-batch-<id>"), so
# the frame id in the RESPONSE is what these examples assert: a view that
# answers a frame the request did not name leaves Turbo with "Content missing".
#
# The detail itself hosts the condensed bookings table (prefix "b"), whose rows
# lazy-load Fin::BookingsController#show as "bkframe-b-<booking id>" -- the
# other half of the same contract, covered in bookings_controller_spec.
describe Fin::BookingBatchesController do
  render_views

  let(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  # Invented header coordinates. The identity index spans consultant/client
  # number, both period dates and the label, so the two batches differ in label.
  def create_batch(label, primanota_number, period_to)
    DatevBookingBatch.create!(consultant_number: "1", client_number: "2",
      label: label, period_from: period_to.beginning_of_month, period_to: period_to,
      financial_year_start: Date.new(2026, 1, 1),
      primanota_number: primanota_number, import_export: "import")
  end

  let!(:batch) { create_batch("Teststapel Alpha", "01-2026/0001", Date.new(2026, 1, 31)) }
  let!(:other_batch) { create_batch("Teststapel Beta", "02-2026/0001", Date.new(2026, 2, 28)) }

  # The Konto is a BANK account, so signed_base_amount is +amount for "D"
  # (see doc/fin/money_conventions.md).
  let!(:booking) do
    DatevBooking.create!(batch: batch, buchungs_guid: SecureRandom.uuid,
      account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
      base_amount: 100, transaction_amount: 100, debit_credit: "D",
      base_currency: "EUR", booking_date: Date.new(2026, 1, 15),
      posting_text: "Testbuchung Alpha")
  end

  before { sign_in(person) }

  def doc = Nokogiri::HTML(response.body)

  # The OUTERMOST turbo frame of the response -- the one the detail view wraps
  # itself in. The batch detail carries further frames below it (one per row of
  # the embedded bookings table), so the first in document order is the one
  # under test.
  def outer_frame_id = doc.at_css("turbo-frame")&.[]("id")

  def frame_ids = doc.css("turbo-frame").pluck("id")

  # The row keys of the rendered list (the widget puts them into the lazy detail
  # frame's DOM id, under the list's own "batch" id prefix).
  def rendered_ids
    response.body.scan(/bkframe-batch-(\d+)/).flatten
  end

  describe "GET index" do
    it "lists the Buchungsstapel, each with its lazy detail frame" do
      get :index
      expect(response).to be_successful
      expect(rendered_ids).to match_array([batch.id.to_s, other_batch.id.to_s])
      expect(response.body).to include("Teststapel Alpha").and include("Teststapel Beta")
    end
  end

  describe "GET show" do
    let(:canonical) { "bkframe-batch-#{batch.id}" }

    it "renders the full detail page, its frame wrapped in #main" do
      get :show, params: {id: batch.id}

      expect(response).to be_successful
      expect(response.body).to include("<html")
      expect(response.body).to include(%(<turbo-frame id="#{canonical}"))
      expect(outer_frame_id).to eq(canonical)
      expect(doc.at_css("turbo-frame##{canonical}").parent["id"]).to eq("main")
      expect(response.body).to include("Teststapel Alpha").and include("Testbuchung Alpha")
    end

    # The embedded bookings table is where the "b"-prefixed frame requests
    # against Fin::BookingsController#show come from: its rows name their detail
    # frames "bkframe-b-<booking id>".
    it "embeds the batch's bookings, each under the 'b' prefix" do
      get :show, params: {id: batch.id}

      expect(frame_ids).to eq([canonical, "bkframe-b-#{booking.id}"])
    end

    # Lazily loaded out of the Buchungsstapel list: the frame it named comes
    # back as the outermost node, and no layout around it.
    it "answers the list's frame without a layout" do
      request.headers["Turbo-Frame"] = canonical
      get :show, params: {id: batch.id, expandable_table_level: "1"}

      expect(response).to be_successful
      expect(response.body).to include(%(<turbo-frame id="#{canonical}"))
      expect(outer_frame_id).to eq(canonical)
      expect(response.body).not_to include("<html")
      expect(response.body).to include("Teststapel Alpha")
    end

    # Any table prefix is accepted as long as the header names a detail frame of
    # THIS batch -- the point of the header is that a second host may embed the
    # same detail under a prefix of its own.
    it "answers a frame named under another table's prefix" do
      request.headers["Turbo-Frame"] = "bkframe-b-#{batch.id}"
      get :show, params: {id: batch.id, expandable_table_level: "2"}

      expect(response).to be_successful
      expect(response.body).to include(%(<turbo-frame id="bkframe-b-#{batch.id}"))
      expect(outer_frame_id).to eq("bkframe-b-#{batch.id}")
      expect(response.body).not_to include("<html")
    end

    # A header is only honoured when it names a detail frame of THIS record. A
    # stray one -- e.g. the redirect of a form submitted inside another row's
    # pane -- falls back to the canonical id, so Turbo never finds two nodes
    # carrying the other row's frame id.
    it "falls back to the canonical id for a header naming another batch" do
      request.headers["Turbo-Frame"] = "bkframe-batch-#{other_batch.id}"
      get :show, params: {id: batch.id}

      expect(response).to be_successful
      expect(outer_frame_id).to eq(canonical)
      expect(frame_ids).not_to include("bkframe-batch-#{other_batch.id}")
    end
  end
end
