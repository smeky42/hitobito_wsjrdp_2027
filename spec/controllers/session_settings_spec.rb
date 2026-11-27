# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The session settings (Wsjrdp2027::Concerns::SessionSettings): the query
# parameter lands in the session, an unknown value clears it, and the cap is
# in force on the very request that sets it.
describe Fin::BookingsController, type: :controller do
  before_all(setup_fixtures: true) {}

  let_it_be(:manager, refind: true) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }
  let_it_be(:reader, refind: true) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }

  let_it_be(:booking) do
    batch = DatevBookingBatch.create!(consultant_number: "1", client_number: "2",
      label: "Teststapel", period_from: Date.new(2026, 1, 1),
      period_to: Date.new(2026, 1, 31), financial_year_start: Date.new(2026, 1, 1),
      primanota_number: "01-2026/0001", import_export: "import")
    DatevBooking.create!(batch: batch, buchungs_guid: SecureRandom.uuid,
      account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "41030", offsetting_account_kind: "INCOME",
      cost_center_number: "9500",
      base_amount: 100, transaction_amount: 100, debit_credit: "D",
      base_currency: "EUR", booking_date: Date.new(2026, 2, 1),
      posting_text: "Testbuchung Alpha")
  end

  let(:ability) { controller.current_ability }

  before { sign_in(manager) }

  it "stores a valid parameter in the session and applies it right away" do
    get :show, params: {id: booking.id, max_finance_permission: "finance_read"}

    expect(response).to be_successful
    expect(session[:max_finance_permission]).to eq("finance_read")
    expect(ability).not_to be_able_to(:update, DatevBooking)
  end

  it "keeps the cap on later requests until it is lifted" do
    session[:max_finance_permission] = "finance_read"
    get :show, params: {id: booking.id}

    expect(ability).not_to be_able_to(:update, DatevBooking)
  end

  it "drops the pick on an empty value, so the default tier applies" do
    session[:max_finance_permission] = "finance_read"
    get :show, params: {id: booking.id, max_finance_permission: ""}

    expect(session[:max_finance_permission]).to be_nil
    expect(ability).to be_able_to(:update, DatevBooking)
    expect(ability).not_to be_able_to(:admin_finance, DatevBooking)
  end

  it "drops a stale session value and behaves as if none were set" do
    session[:max_finance_permission] = "no_such_tier"
    get :show, params: {id: booking.id}

    expect(session[:max_finance_permission]).to be_nil
    expect(controller.max_finance_permission).to be_nil
    expect(ability).to be_able_to(:update, DatevBooking)
  end

  # A role grants the manage tier, the session decides whether it is exercised.
  it "leaves the manage tier out until it is picked, and never writes the key on its own" do
    get :show, params: {id: booking.id}

    expect(session).not_to have_key(:max_finance_permission)
    expect(ability.user_context.finance_tier_by_roles).to eq(:finance_manage)
    expect(ability.user_context.finance_tier).to eq(:finance)
    expect(ability).to be_able_to(:update, DatevBooking)
    expect(ability).not_to be_able_to(:admin_finance, DatevBooking)
  end

  it "hands the manage tier out on a pick" do
    get :show, params: {id: booking.id, max_finance_permission: "finance_manage"}

    expect(ability).to be_able_to(:admin_finance, DatevBooking)
  end

  it "takes the tier from the roles of the request" do
    sign_in(reader)
    get :show, params: {id: booking.id}

    expect(ability.user_context.finance_tier).to eq(:finance_read)
    expect(ability).not_to be_able_to(:update, DatevBooking)
  end

  it "drops a pick the roles no longer cover" do
    sign_in(reader)
    session[:max_finance_permission] = "finance_manage"
    get :show, params: {id: booking.id}

    expect(session[:max_finance_permission]).to be_nil
    expect(ability.user_context.finance_tier).to eq(:finance_read)
  end

  it "drops an unknown bar mode and is back on demand" do
    session[:finance_tier_bar] = "sometimes"
    get :show, params: {id: booking.id}

    expect(controller.finance_tier_bar).to eq(:ondemand)
    expect(session[:finance_tier_bar]).to be_nil
  end

  it "drops an unknown admin tab mode and is back to hidden" do
    session[:admin_tab] = "sometimes"
    get :show, params: {id: booking.id}

    expect(controller.admin_tab).to eq(:hidden)
    expect(session[:admin_tab]).to be_nil
  end

  it "refuses a write the cap took away, in the controller too" do
    session[:max_finance_permission] = "finance_read"

    expect do
      patch :update, params: {id: booking.id, datev_booking: {sub_cost_center_number: "X1"}}
    end.to raise_error(CanCan::AccessDenied)
  end
end

# The session UI's background target. The admin tab mode is mirrored into the
# preference of the person who actually logged in, so it survives the login.
describe SessionSettingsController, type: :controller do
  before_all(setup_fixtures: true) {}

  let_it_be(:person, refind: true) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }
  let(:member) { people(:cmt_member1) }

  def persisted(someone) = Person.find(someone.id).wsjrdp_preference_admin_tab

  before { sign_in(person) }

  it "stores a cap and answers without a body" do
    post :update, params: {max_finance_permission: "finance_read"}

    expect(response).to have_http_status(:no_content)
    expect(session[:max_finance_permission]).to eq("finance_read")
  end

  it "lifts it on an empty value" do
    session[:max_finance_permission] = "finance_read"
    post :update, params: {max_finance_permission: ""}

    expect(session[:max_finance_permission]).to be_nil
  end

  it "stores the bar mode the same way" do
    post :update, params: {finance_tier_bar: "hidden"}

    expect(session[:finance_tier_bar]).to eq("hidden")
  end

  describe "the admin tab mode" do
    it "is written to the session and the persisted preference" do
      post :update, params: {admin_tab: "ondemand"}

      expect(session[:admin_tab]).to eq("ondemand")
      expect(persisted(person)).to eq("ondemand")
    end

    it "reads a truthy spelling as always" do
      post :update, params: {admin_tab: "YES"}

      expect(session[:admin_tab]).to eq("always")
      expect(persisted(person)).to eq("always")
    end

    it "reads a falsy spelling as hidden" do
      session[:admin_tab] = "always"
      post :update, params: {admin_tab: "off"}

      expect(session[:admin_tab]).to eq("hidden")
      expect(persisted(person)).to eq("hidden")
    end

    it "leaves an unknown, non-blank value alone: neither stored nor a reset" do
      person.wsjrdp_preference_admin_tab = "always"
      post :update, params: {admin_tab: "sometimes"}

      expect(session[:admin_tab]).to be_nil
      expect(persisted(person)).to eq("always")
    end

    it "is cleared in both places by a blank value" do
      person.wsjrdp_preference_admin_tab = "always"
      session[:admin_tab] = "always"
      post :update, params: {admin_tab: ""}

      expect(session[:admin_tab]).to be_nil
      expect(persisted(person)).to be_nil
    end

    it "seeds a fresh session from the persisted preference, without writing it again" do
      person.wsjrdp_preference_admin_tab = "ondemand"

      expect { post :update }.not_to(change { persisted(person) }.from("ondemand"))
      expect(session[:admin_tab]).to eq("ondemand")
    end

    describe "while impersonating" do
      before do
        sign_in(member)
        session[:origin_user] = person.id
      end

      it "writes the preference of the origin user, never the impersonated one's" do
        post :update, params: {admin_tab: "always"}

        expect(persisted(person)).to eq("always")
        expect(persisted(member)).to be_nil
      end

      it "seeds a fresh session from the origin user's preference" do
        person.wsjrdp_preference_admin_tab = "ondemand"
        post :update

        expect(session[:admin_tab]).to eq("ondemand")
      end
    end
  end
end

# The admin tab's person search: impersonate, or switch out of a running
# impersonation, always as the person who actually logged in.
describe Wsjrdp::ImpersonationController, type: :controller do
  before_all(setup_fixtures: true) {}

  let_it_be(:admin, refind: true) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }
  let_it_be(:manager, refind: true) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }
  let(:member) { people(:cmt_member1) }

  def signed_in = request.env["warden"].user(:person)

  def events(person) = PaperTrail::Version.where(main: person).pluck(:event)

  it "routes" do
    expect(post: "/wsjrdp/impersonate").to route_to(controller: "wsjrdp/impersonation", action: "create")
  end

  it "impersonates for an admin, with the core's bookkeeping" do
    sign_in(admin)
    post :create, params: {person_id: member.id}

    expect(response).to redirect_to(root_path)
    expect(session[:origin_user]).to eq(admin.id)
    expect(signed_in).to eq(member)
    expect(events(member)).to eq(["impersonate"])
  end

  # The menu hands the page along so nobody is moved off it by impersonating.
  it "comes back to the page it was called from" do
    sign_in(admin)
    post :create, params: {person_id: member.id, return_to: "/fin/acc/2?q=x"}

    expect(response).to redirect_to("/fin/acc/2?q=x")
  end

  it "ignores a return_to that leaves this site" do
    ["https://example.com/x", "//example.com/x", "/\\example.com", "javascript:alert(1)", ""].each do |path|
      session[:origin_user] = nil
      sign_in(admin)
      post :create, params: {person_id: member.id, return_to: path}

      expect(response).to redirect_to(root_path)
    end
  end

  it "switches out of a running impersonation, the origin user staying the taker and deciding" do
    sign_in(member) # the admin is impersonating the member
    session[:origin_user] = admin.id
    allow(Ability).to receive(:new).and_call_original
    post :create, params: {person_id: manager.id}

    expect(response).to redirect_to(root_path)
    expect(session[:origin_user]).to eq(admin.id)
    expect(signed_in).to eq(manager)
    expect(events(member)).to eq(["impersonation_done"])
    expect(events(manager)).to eq(["impersonate"])
    expect(Ability).to have_received(:new).with(admin) # the origin user's rights, not the member's
  end

  # Whether a person may impersonate is the core's rule (:impersonation);
  # here only that a refusal stops everything. (The dev core carries a local
  # rule that lets anyone, so the refusal is stubbed rather than provoked.)
  it "refuses whoever the ability refuses, before anything happens" do
    sign_in(manager)
    ability = Ability.new(manager)
    allow(ability).to receive(:can?).and_call_original
    allow(ability).to receive(:can?).with(:impersonate_user, Person).and_return(false)
    allow(controller).to receive(:current_ability).and_return(ability)

    expect { post :create, params: {person_id: member.id} }.to raise_error(CanCan::AccessDenied)
    expect(session[:origin_user]).to be_nil
    expect(events(member)).to be_empty
  end

  it "does nothing for oneself" do
    sign_in(admin)
    post :create, params: {person_id: admin.id}

    expect(response).to redirect_to(root_path)
    expect(session[:origin_user]).to be_nil
  end

  it "does nothing for the person already impersonated" do
    sign_in(member)
    session[:origin_user] = admin.id
    post :create, params: {person_id: member.id}

    expect(session[:origin_user]).to eq(admin.id)
    expect(signed_in).to eq(member)
    expect(events(member)).to be_empty
  end
end
