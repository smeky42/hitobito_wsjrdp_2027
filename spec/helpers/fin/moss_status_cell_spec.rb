# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The "Moss Status" cell of the Buchhaltung summary tables.
describe Fin::BookkeepingHelper do
  def cell(status) = Nokogiri::HTML.fragment(helper.moss_status_cell(status)).at_css("span")

  it "tints an active status as aktiv and every other, NULL included, as inaktiv" do
    aggregate_failures do
      expect([cell("active")["class"], cell("active").text]).to eq(["moss-status moss-status-active", "aktiv"])
      expect([cell("deactivated")["class"], cell("deactivated").text])
        .to eq(["moss-status moss-status-inactive", "inaktiv"])
      expect([cell(nil)["class"], cell(nil).text]).to eq(["moss-status moss-status-inactive", "inaktiv"])
    end
  end
end
