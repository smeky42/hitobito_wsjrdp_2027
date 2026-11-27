# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe "people/_family_attrs" do
  let(:yp) { people(:yp_a_1) }

  def page_for(editable:)
    allow(view).to receive(:can?).and_return(false)
    allow(view).to receive(:can?).with(:update_family, yp).and_return(editable)
    allow(view).to receive(:can?).with(:show, people(:ul_a_1)).and_return(true)
    render partial: "people/family_attrs", locals: {person: yp}
    Capybara.string(rendered)
  end

  it "lists parents first, links only whom the viewer may see and offers no edit without the right" do
    FamilyMember.create!(person: yp, other: people(:admin), kind: "sibling")
    FamilyMember.create!(person: yp, other: people(:ul_a_1), kind: "parent")

    page = page_for(editable: false)

    aggregate_failures do
      expect(page.all("table tr").map(&:text)).to match([people(:ul_a_1), people(:admin)]
        .map { |person| a_string_including(person.short_full_name_with_nickname) })
      expect(page).to have_css("a", text: people(:ul_a_1).short_full_name_with_nickname)
      expect(page).to have_no_css("a", text: people(:admin).short_full_name_with_nickname)
      expect(page).to have_no_css("a[href='#{edit_person_family_members_path(yp)}']")
    end
  end

  it "shows the section without family only to whom may edit it" do
    expect(page_for(editable: false)).to have_no_css("section")
    expect(page_for(editable: true)).to have_css("section a[href='#{edit_person_family_members_path(yp)}']")
  end
end
