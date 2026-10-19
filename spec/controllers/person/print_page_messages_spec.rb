# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The print page says on the page itself what is missing for printing; it
# leaves no flash behind for the next page.
describe Person::PrintController do
  render_views

  let(:person) { people(:yp_a_1) }

  before { sign_in(people(:admin)) }

  def alert_text = Nokogiri::HTML(response.body).css("#main .alert-danger").text.squish

  it "shows what is missing for a registered person, without a flash" do
    person.update_columns(status: "registered", sepa_iban: "invalid")

    get(:index, params: {id: person.id})

    expect(response).to be_successful
    expect(alert_text).to start_with(I18n.t("people.alerts.print_missing_fields"))
    expect(alert_text).to include(I18n.t("people.alerts.iban"))
    expect(flash.to_h).to be_empty
  end

  it "shows no alert and no flash for a printed person" do
    person.update_columns(status: "printed", sepa_iban: "invalid")

    get(:index, params: {id: person.id})

    expect(response).to be_successful
    expect(alert_text).to be_empty
    expect(flash.to_h).to be_empty
  end
end
