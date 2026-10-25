# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp2027::StandardFormBuilder, type: :helper do
  let(:form) { StandardFormBuilder.new(:person, people(:yp_a_1), helper, {}) }
  let(:button) { helper.tag.button("Zusatz") }

  it "puts the aside of a labeled field between the field and its help, with its script once" do
    html = form.labeled_input_field(:sepa_name, aside: button, help: "Hilfe") +
      form.labeled_input_field(:sepa_mail, aside: button)
    page = Capybara.string(html)

    box = page.find(".labeled", match: :first).find(".wsjrdp-field-aside")
    expect(box).to have_css(".wsjrdp-field-aside-field input#person_sepa_name")
    expect(box).to have_css(".wsjrdp-field-aside-content button", text: "Zusatz")
    expect(page).to have_css(".wsjrdp-field-aside ~ .form-text", text: "Hilfe")
    expect(html.scan("wsjrdpFieldAside =").size).to eq(1)
  end

  it "leaves a labeled field without aside as it is" do
    expect(form.labeled_input_field(:sepa_name, aside: nil)).not_to include("wsjrdp-field-aside")
  end
end
