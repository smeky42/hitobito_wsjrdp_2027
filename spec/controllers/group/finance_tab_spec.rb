# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The "Finanzen" tab on the group page: it is declared with `if: :show_finance`,
# so it only reaches the people who may open the page behind it.
describe GroupsController do
  render_views

  let(:group) { groups(:unit_a) }

  it "shows the tab to a unit leader on their own unit" do
    sign_in(people(:ul_a_1))

    get :show, params: {id: group.id}

    expect(response).to be_successful
    expect(response.body).to include(group_finance_bookkeeping_path(group))
    expect(response.body).to include("Finanzen")
  end

  it "hides the tab from a youth participant" do
    sign_in(people(:yp_a_1))

    get :show, params: {id: group.id}

    expect(response).to be_successful
    expect(response.body).not_to include(group_finance_bookkeeping_path(group))
  end
end
