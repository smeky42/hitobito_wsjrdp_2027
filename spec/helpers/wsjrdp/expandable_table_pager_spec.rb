# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The pager of the expandable table, the wagon's Kaminari theme "wsjrdp": the
# two icon-only step buttons first and always, then the page numbers with page
# 1 and the last page spelled out. Twelve pages of one row each, so the first
# and the last one fall outside the window of four and the gap shows.
describe "the expandable table's pager", type: :helper do
  def pager(page)
    rows = Kaminari.paginate_array(Array.new(12)).page(page).per(1)
    html = helper.paginate(rows, theme: "wsjrdp", window: 4, left: 1, right: 1, param_name: :p,
      params: {controller: "fin/ledger_accounts", action: "index", o: nil})
    Nokogiri::HTML.fragment(html).css(".pagination li")
  end

  def labels(items) = items.map { |li| li.at_css("[aria-label]")&.[]("aria-label") || li.text.strip }

  def steps(items) = items.select { |li| li["class"].to_s.include?("bk-page-step") }

  before { controller.params[:o] = "1200" }

  it "leads with the step buttons and spells out the first and the last page, without the open rows" do
    items = pager(6)
    hrefs = items.css("a.page-link").pluck("href")

    aggregate_failures do
      expect(labels(items)).to eq(["Vorherige Seite", "Nächste Seite",
        "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "...", "12"])
      expect(hrefs).to include(a_string_matching(/\bp=1\b/)).and include(a_string_matching(/\bp=12\b/))
      expect(hrefs).to all(satisfy { |href| !href.include?("o=") })
    end
  end

  it "disables the step back on the first page and links the step forward" do
    prev_item, next_item = steps(pager(1))

    aggregate_failures do
      expect(prev_item["class"]).to include("disabled")
      expect(prev_item.at_css("a")).to be_nil
      expect(prev_item.at_css("span.page-link")["aria-disabled"]).to eq("true")
      link = next_item.at_css("a.page-link")
      expect(link["rel"]).to eq("next")
      expect(link["href"]).to match(/\bp=2\b/)
    end
  end

  it "disables the step forward on the last page and keeps it in place" do
    items = pager(12)
    prev_item, next_item = steps(items)

    aggregate_failures do
      expect(labels(items).first(2)).to eq(["Vorherige Seite", "Nächste Seite"])
      expect(next_item["class"]).to include("disabled")
      expect(next_item.at_css("a")).to be_nil
      expect(prev_item.at_css("a.page-link")["href"]).to match(/\bp=11\b/)
    end
  end
end
