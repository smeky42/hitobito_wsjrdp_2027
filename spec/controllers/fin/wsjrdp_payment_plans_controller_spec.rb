# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Ratenpläne tab of the Beiträge area: the standard plans, for everyone of
# the area down to the read tier.
describe Fin::WsjrdpPaymentPlansController do
  render_views

  let(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }

  before do
    # The migrated standard plans aside: the example sets up its own.
    WsjrdpPaymentPlan.kept.destroy_all
    WsjrdpPaymentPlan.create!(wsjrdp_role: "UL", single_payment: false, payment_method: "direct_debit",
      raw_installments_eur: [2025, *([0] * 11), 150, 350])
  end

  it "lists the standard plans" do
    sign_in(reader)
    get :index

    expect(response).to be_successful
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("#main h1").text).to eq "Ratenpläne"
    expect(doc.css("#main h2")).to be_empty
    row = doc.css("#main table tbody tr").find { |tr| tr.text.include?("UL") }
    expect(row.css("td").map { |td| td.text.squish }).to eq(["UL", "Nein", "2025-12: 150€, 2026-01: 350€", "Lastschrift", "500 €", ""])
    expect(response.body).not_to include("Individuelle Ratenpläne")
  end
end
