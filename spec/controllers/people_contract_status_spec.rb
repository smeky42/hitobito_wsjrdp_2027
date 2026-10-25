# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The contract in a word, in colour, beside the registration status in the
# person's aside (people/_status).
describe PeopleController, type: :controller do
  render_views

  let(:yp) { people(:yp_a_1) }

  before { sign_in(people(:admin)) }

  {"none" => "text-muted", "confirmed" => "fin-status-confirmed",
   "replacement_pending" => "fin-status-noted", "ended" => "fin-status-deregistered"}.each do |status, css|
    it "shows the contract #{status} coloured" do
      yp.update_columns(contract_status: status)
      get :show, params: {group_id: yp.primary_group_id, id: yp.id}

      contract = Nokogiri::HTML(response.body).css("aside dt").find { |dt| dt.text.strip == "Vertrag" }.next_element
      expect(contract.at_css("span.#{css}").text).to eq(Settings.contract_status[status])
    end
  end
end
