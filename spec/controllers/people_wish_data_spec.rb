# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The buddy wishes on the person's page (people/_participant_wish_data).
describe PeopleController, type: :controller do
  render_views

  let(:yp) { people(:yp_a_1) }
  let(:wished_header) { I18n.t("people.participant_wish_data.header_wished_yp_buddy") }

  before { sign_in(people(:admin)) }

  def show = get(:show, params: {group_id: yp.primary_group_id, id: yp.id})

  it "lists nobody as wishing for a person without a buddy id" do
    yp.update_columns(buddy_id: nil)
    people(:yp_a_2).update_columns(buddy_id_yp: nil)

    show

    expect(response.body).not_to include(wished_header)
  end

  it "lists who wished for the person by their buddy id" do
    yp.update_columns(buddy_id: "spice")
    people(:yp_a_2).update_columns(buddy_id_yp: "spice-#{yp.id}")

    show

    expect(response.body).to include(wished_header).and include(people(:yp_a_2).last_name)
  end
end
