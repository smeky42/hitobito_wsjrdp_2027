# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The person fee page (/people/:id/fee). Its sheet hangs below the group sheet,
# whose left navigation needs a group: PersonInPrimaryGroup supplies the
# person's primary group, or the root group for a person without one -- the
# root user has no role at all, and its page used to fail in that navigation.
describe Person::FeeController do
  render_views

  # Nobody but the person themselves may edit a person who is in no layer, so
  # the page is opened by its owner -- as the root user opens their own.
  it "renders a person without any role in the root group" do
    person = Fabricate(:person)
    expect(person.primary_group).to be_nil
    # The installments block reads the person's payment plan (by wsjrdp_role and
    # payment mode). A database built by the migrations already holds one per
    # role (20260419000100 seeds them, as CI does); a schema-loaded test
    # database holds none -- so take the existing plan or create one.
    WsjrdpPaymentPlan.find_or_create_by!(wsjrdp_role: person.wsjrdp_role, single_payment: false) do |plan|
      plan.raw_installments_eur = [2026, 100, 100]
    end
    sign_in(person)

    get :show, params: {person_id: person.id}
    expect(response).to be_successful
    expect(assigns(:group)).to eq(Group.root)
  end
end
