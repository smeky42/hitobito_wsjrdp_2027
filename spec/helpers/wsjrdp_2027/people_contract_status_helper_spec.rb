# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp2027::PeopleHelper do
  it "shows the contract in a word, coloured by its status, none grey", :aggregate_failures do
    {"none" => "text-muted", "confirmed" => "fin-status-confirmed",
     "replacement_pending" => "fin-status-noted", "ended" => "fin-status-deregistered"}.each do |status, css|
      tag = Nokogiri::HTML.fragment(helper.format_person_contract_status(Person.new(contract_status: status)))

      expect(tag.at_css("span.#{css}")&.text).to eq(Settings.contract_status[status])
    end
  end
end
