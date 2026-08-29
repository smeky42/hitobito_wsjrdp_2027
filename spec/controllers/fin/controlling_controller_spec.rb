# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Controlling overview: the (still empty) page of the last Finanzen area,
# and the left sub-navigation its area sheet renders.
describe Fin::ControllingController do
  render_views

  let(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  before { sign_in(person) }

  # [label, active?] per entry of the Finanzen sub-navigation, in menu order.
  # The sub-nav is the nav-left-list nested inside the active main-nav item.
  def left_nav_entries
    Nokogiri::HTML(response.body).css("li.nav-left-section ul.nav-left-list > li").map do |li|
      [li.text.strip, li["class"].to_s.split.include?("is-active")]
    end
  end

  it "renders the still empty overview page" do
    get :index
    expect(response).to be_successful
    expect(response.body).to include("Controlling").and include("Dieser Bereich ist noch leer.")
  end

  it "renders the six Finanzen areas next to Übersicht, Controlling active" do
    get :index
    expect(left_nav_entries.map(&:first)).to eq(
      [I18n.t("fin.nav.overview"), I18n.t("fin.nav.accounts"), I18n.t("fin.nav.fees"),
        I18n.t("fin.nav.moss"), I18n.t("fin.nav.accounting"),
        I18n.t("fin.nav.reconciliation"), I18n.t("fin.nav.controlling")]
    )
    # Exactly one entry is marked, and it is this area.
    expect(left_nav_entries.select(&:last).map(&:first)).to eq([I18n.t("fin.nav.controlling")])
  end
end
