# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The turbo frame a detail view answers in. One detail is lazy-loaded from
# tables with different prefixes (the Buchungen list asks as "bkframe-bk-<id>",
# the bookings table inside a Buchhaltung item detail as "bkframe-b-<id>"), so
# the frame named by the request is the one that comes back.
describe WsjrdpFormHelper, type: :helper do
  def frame(header = nil)
    helper.request.headers["Turbo-Frame"] = header if header
    Nokogiri::HTML.fragment(helper.wsjrdp_detail_frame("bk", 7) { "Detail" })
  end

  def frame_ids(html) = html.css("turbo-frame").pluck("id")

  it "wraps a direct visit in #main under the canonical id" do
    html = frame

    aggregate_failures do
      expect(frame_ids(html)).to eq(["bkframe-bk-7"])
      expect(html.at_css("turbo-frame").parent["id"]).to eq("main")
    end
  end

  it "answers the frame the request names, without #main" do
    html = frame("bkframe-b-7")

    aggregate_failures do
      expect(frame_ids(html)).to eq(["bkframe-b-7"])
      expect(html.at_css("#main")).to be_nil
    end
  end

  # A stray header -- e.g. the redirect of a form submitted inside another
  # row's pane -- must not rename this page's frame to the other row's id.
  it "falls back to the canonical id for a header naming another record" do
    expect(frame_ids(frame("bkframe-bk-8"))).to eq(["bkframe-bk-7"])
  end
end
