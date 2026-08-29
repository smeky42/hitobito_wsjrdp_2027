# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Beiträge overview: the page that links the two lists of the area, the
# tabs its area sheet renders and the left sub-navigation.
describe Fin::FeesController do
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

  # [label, href] of every link inside #main.
  def main_links
    Nokogiri::HTML(response.body).css("#main a").map { |a| [a.text.strip, a["href"]] }
  end

  it "names the area and says what it is for" do
    get :index
    expect(response).to be_successful
    expect(response.body).to include(I18n.t("fin.nav.fees"))
      .and include(I18n.t("fin.areas.fees.purpose"))
  end

  # The two lists of the area, each with the small new-tab companion icon
  # behind it -- the same pairing the /fin card shows.
  it "links the two lists, each also in a new tab" do
    get :index

    expect(main_links).to include(
      [I18n.t("fin.tabs.person_fees"), fin_person_fees_path],
      [I18n.t("fin.tabs.plans"), wsjrdp_payment_plans_path]
    )
    newtabs = Nokogiri::HTML(response.body).css("#main ul.list-unstyled a[target='_blank']")
    expect(newtabs.pluck("href")).to eq([fin_person_fees_path, wsjrdp_payment_plans_path])
  end

  # Übersicht is an exact-match tab: on this page it is the active one.
  it "renders the three tabs of the area, Übersicht active" do
    get :index

    tabs = Nokogiri::HTML(response.body).css("ul.nav-sub > li")
    expect(tabs.map { |li| li.text.strip }).to eq(
      [I18n.t("fin.tabs.overview"), I18n.t("fin.tabs.person_fees"), I18n.t("fin.tabs.plans")]
    )
    active = tabs.select { |li| li["class"].to_s.split.include?("active") }
    expect(active.map { |li| li.text.strip }).to eq([I18n.t("fin.tabs.overview")])
  end

  it "renders the six Finanzen areas next to Übersicht, Beiträge active" do
    get :index

    expect(left_nav_entries.map(&:first)).to eq(
      [I18n.t("fin.nav.overview"), I18n.t("fin.nav.accounts"), I18n.t("fin.nav.fees"),
        I18n.t("fin.nav.moss"), I18n.t("fin.nav.accounting"),
        I18n.t("fin.nav.reconciliation"), I18n.t("fin.nav.controlling")]
    )
    # Exactly one entry is marked, and it is this area.
    expect(left_nav_entries.select(&:last).map(&:first)).to eq([I18n.t("fin.nav.fees")])
  end
end
