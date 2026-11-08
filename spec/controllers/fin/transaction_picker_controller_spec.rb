# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Fin::TransactionPickerController do
  render_views

  let!(:giro) { it_account("Giro", iban: InternalTransferSpecHelpers::GIRO_IBAN) }
  let(:day) { Date.new(2026, 3, 5) }
  let!(:out) { it_camt(giro, -677.48, day, cdtr_name: "Musterverein") }
  let!(:into) { it_camt(giro, 50, day) }
  let(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }

  def doc = Nokogiri::HTML(response.body)

  before { sign_in(reader) }

  it "answers the picker's frame with the matching rows, unnamed, carrying key and amount" do
    get :index, params: {picker: "it-1-from", sign: "out", from: "2026-03-01", to: "2026-03-10"}

    frame = doc.at_css("turbo-frame#tp-results-it-1-from")
    box = frame.at_css("input[data-tp-pick]")
    expect(box["data-tp-pick"]).to eq(out.internal_transfer_leg_key)
    expect(box["data-amount"]).to eq("-677.48")
    expect(box["name"]).to be_nil
    expect(frame.text).to include("1 Treffer", "Musterverein", "-677,48")
  end

  it "shows a row of a transfer disabled, with a link to it" do
    transfer = WsjrdpInternalTransfer.link!([out])
    get :index, params: {picker: "p", linked: "1", sign: "out"}

    expect(doc.at_css("input[data-tp-pick]")["disabled"]).to be_present
    expect(doc.at_css("a[href='/fin/acc/internal_transfers/#{transfer.id}']")).to be_present
  end

  it "says when it does not understand the amount" do
    get :index, params: {picker: "p", amount: "viel"}

    expect(response.body).to include("Betrag nicht verstanden")
  end

  it "keeps the picker id to safe characters" do
    get :index, params: {picker: "a\"><b"}

    expect(doc.at_css("turbo-frame")["id"]).to eq("tp-results-ab")
  end

  it "is closed without a finance tier" do
    sign_in(people(:cmt_member1))
    expect { get :index }.to raise_error(CanCan::AccessDenied)
  end
end
