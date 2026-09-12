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
  render_views

  let(:manager) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }

  let!(:batch) do
    DatevBookingBatch.create!(consultant_number: "1", client_number: "2",
      label: "Teststapel", period_from: Date.new(2026, 1, 1),
      period_to: Date.new(2026, 1, 31), financial_year_start: Date.new(2026, 1, 1),
      primanota_number: "01-2026/0001", import_export: "import")
  end

  let!(:booking) do
    DatevBooking.create!(batch: batch, buchungs_guid: SecureRandom.uuid,
      account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "41030", offsetting_account_kind: "INCOME",
      cost_center_number: "9500",
      base_amount: 100, transaction_amount: 100, debit_credit: "D",
      base_currency: "EUR", booking_date: Date.new(2026, 2, 1),
      posting_text: "Testbuchung Alpha")
  end

  before { sign_in(manager) }

  # The field-edit form only exists for :fin_admin -- the visible tell of the
  # top tier on this page.
  def field_form? = response.body.include?("datev_booking[secondary_cost_center_number]")

  it "stores a valid parameter in the session and applies it right away" do
    get :show, params: {id: booking.id, max_finance_permission: "finance_read"}

    expect(session[:max_finance_permission]).to eq("finance_read")
    expect(response).to be_successful
    expect(field_form?).to be(false)
    expect(controller.current_ability).not_to be_able_to(:update, DatevBooking)
  end

  it "keeps the cap on later requests until it is lifted" do
    session[:max_finance_permission] = "finance"
    get :show, params: {id: booking.id}

    expect(controller.current_ability).to be_able_to(:update, DatevBooking)
    expect(controller.current_ability).not_to be_able_to(:fin_admin, DatevBooking)
    expect(field_form?).to be(false)
  end

  it "clears the cap on an unknown or empty value" do
    session[:max_finance_permission] = "finance_read"
    get :show, params: {id: booking.id, max_finance_permission: ""}

    expect(session[:max_finance_permission]).to be_nil
    expect(field_form?).to be(true)
  end

  it "drops a stale session value and behaves as if none were set" do
    session[:max_finance_permission] = "no_such_tier"
    get :show, params: {id: booking.id}

    expect(session[:max_finance_permission]).to be_nil
    expect(controller.max_finance_permission).to be_nil
    expect(field_form?).to be(true)
  end

  # The session bars (layouts/_wsjrdp_session_bar, doc/roles.md -> "The
  # finance cap"): a red one while impersonating, a yellow one that IS the
  # tier selection -- a segmented control of the tiers up to the roles' own,
  # the tier in force pressed -- shown by the session's finance_tier_bar mode.
  # Every action is a background button (no href, no rails-ujs data-method).
  describe "the session bars" do
    def doc = Nokogiri::HTML(response.body)

    def bars = doc.css(".wsjrdp-session-bar")

    def danger = doc.at_css(".wsjrdp-session-bar .alert-danger")

    def warning = doc.at_css(".wsjrdp-session-bar .alert-warning")

    # [label, pressed?, url] per segment, in rank order.
    def segments
      warning.css(".wsjrdp-seg button").map { |b| [b.text.strip, b["aria-pressed"] == "true", b["data-url"]] }
    end

    # The bar's one action: [method, url query as a hash, label text, icon?].
    def action(alert)
      button = alert.at_css("button.wsjrdp-bar-action")
      [button["data-wsjrdp-session-action"], Rack::Utils.parse_query(URI(button["data-url"]).query),
        button.at_css(".wsjrdp-bar-action-label").text.strip, button.at_css("i.fa-times-circle").present?]
    end

    # The tier names as the locale spells them (wsjrdp.finance_tiers).
    def tier(permission) = I18n.t("wsjrdp.finance_tiers.#{permission}")

    # The core's logo is positioned absolutely, so it has to be pushed down by
    # the height of the bars -- otherwise it sits under them.
    def logo_offset = response.body[/header\.logo \{ margin-top: (\d+)px; \}/, 1]&.to_i

    it "shows nothing without a cap (ondemand)" do
      get :show, params: {id: booking.id}

      expect(bars).to be_empty
      expect(logo_offset).to be_nil
    end

    it "offers every tier up to the roles' own, the one in force pressed, while the cap lowers the tier" do
      session[:max_finance_permission] = "finance_audit"
      get :show, params: {id: booking.id}

      expect(bars.size).to eq(1)
      expect(danger).to be_nil
      expect(segments).to eq([
        [tier(:finance_read), false, "/session_settings?max_finance_permission=finance_read"],
        [tier(:finance_audit), true, "/session_settings?max_finance_permission=finance_audit"],
        [tier(:finance), false, "/session_settings?max_finance_permission=finance"],
        [tier(:finance_manage), false, "/session_settings?max_finance_permission="] # the roles' tier clears the cap
      ])
      expect(warning.text).to include("(nach Rolle: #{tier(:finance_manage)})")
      # "Begrenzung aufheben" clears the cap AND puts the bar back on demand.
      expect(action(warning)).to eq(["post", {"max_finance_permission" => "", "finance_tier_bar" => "ondemand"},
        I18n.t("layouts.wsjrdp_session_bar.lift"), true])
      expect(warning.css("a, [data-method], .wsjrdp-bar-close")).to be_empty
      expect(logo_offset).to eq(30)
    end

    it "shows the bar on demand as soon as a cap is set, even one that changes nothing" do
      reader = Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person
      sign_in(reader)
      session[:max_finance_permission] = "finance_manage"
      get :show, params: {id: booking.id}

      expect(segments).to eq([[tier(:finance_read), true, "/session_settings?max_finance_permission="]])
    end

    it "keeps the bar with finance_tier_bar=always, and never shows it with hidden" do
      get :show, params: {id: booking.id, finance_tier_bar: "always"}

      expect(session[:finance_tier_bar]).to eq("always")
      expect(segments.map(&:first)).to eq(%i[finance_read finance_audit finance finance_manage].map { |p| tier(p) })
      expect(segments.last[1]).to be(true)

      session[:max_finance_permission] = "finance_read"
      get :show, params: {id: booking.id, finance_tier_bar: "hidden"}

      expect(session[:finance_tier_bar]).to eq("hidden")
      expect(bars).to be_empty
      expect(controller.current_ability).not_to be_able_to(:update, DatevBooking) # the cap still applies
    end

    it "drops an unknown mode and is back on demand" do
      session[:finance_tier_bar] = "sometimes"
      get :show, params: {id: booking.id}

      expect(session[:finance_tier_bar]).to be_nil
      expect(controller.finance_tier_bar).to eq(:ondemand)
    end

    it "stacks the red and the yellow bar while impersonating with a cap" do
      session[:origin_user] = people(:cmt_leader).id
      session[:max_finance_permission] = "finance_read"
      get :show, params: {id: booking.id}

      expect(bars.size).to eq(2)
      expect(bars.first.at_css(".alert-danger")).to be_present
      expect(bars.last.at_css(".alert-warning")).to be_present
      expect(action(danger)).to eq(["delete", {}, I18n.t("layouts.user_impersonation.end"), true])
      expect(danger.at_css("button.wsjrdp-bar-action")["data-url"])
        .to eq("/groups/#{manager.primary_group_id}/people/#{manager.id}/impersonate")
      expect(segments.map(&:second)).to eq([true, false, false, false])
      expect(doc.css(".info-bar").size).to eq(4) # download spinner, sync spinner, red, yellow
      expect(doc.css(".user-impersonation")).to be_empty # the core's own bar is silenced
      expect(logo_offset).to eq(60) # the logo clears both bars
    end

    it "shows only the red bar, with the end button, while impersonating without a cap" do
      session[:origin_user] = people(:cmt_leader).id
      get :show, params: {id: booking.id}

      expect(bars.size).to eq(1)
      expect(warning).to be_nil
      expect(danger.text).to include("angemeldet")
      expect(danger.css("button[data-wsjrdp-session-action]").size).to eq(1)
      expect(action(danger).first).to eq("delete")
    end
  end

  # The admin tab (layouts/_wsjrdp_session_bar, doc/roles.md -> "The finance
  # cap"): a menu for whoever ACTUALLY logged in with :admin (the origin user
  # while impersonating), shown by the session's compact_admin_tab mode --
  # always, or on demand while one of the bars is missing -- and never
  # without asking. The menu: the tiers up to the roles' own, the bar
  # switches, the person search for whoever may impersonate (Group::Root::Admin holds
  # :impersonation), and "Imitation beenden" while impersonating.
  describe "the admin tab" do
    let(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }

    def doc = Nokogiri::HTML(response.body)

    def tab = doc.at_css(".wsjrdp-admin-tab")

    # [label, in force?, url] per tier entry, in rank order.
    def tiers
      tab.css("button.wsjrdp-admin-tab-tier").map { |b| [b.text.squish, b["aria-current"] == "true", b["data-url"]] }
    end

    # [url, disabled?] of the show and the hide switch.
    def bar_switches
      %w[show hide].map { |kind|
        b = tab.at_css("button.wsjrdp-admin-tab-bar-#{kind}")
        [b["data-url"], b["disabled"].present?]
      }
    end

    def picker = tab.at_css("input[data-wsjrdp-impersonate-url]")

    def tier(permission) = I18n.t("wsjrdp.finance_tiers.#{permission}")

    it "is not there unless asked for, not even for an admin" do
      sign_in(admin)
      get :show, params: {id: booking.id}

      expect(tab).to be_nil
    end

    it "is withheld from a manager without :admin, however asked" do
      get :show, params: {id: booking.id, compact_admin_tab: "always"}

      expect(session[:compact_admin_tab]).to eq("always")
      expect(tab).to be_nil
    end

    it "shows for an admin with compact_admin_tab=always: the tiers, the bar switches, the person search" do
      sign_in(admin)
      get :show, params: {id: booking.id, compact_admin_tab: "always"}

      expect(tab).to be_present
      expect(tab.at_css("button[data-bs-toggle=dropdown]").text).to include(I18n.t("layouts.wsjrdp_session_bar.admin_tab"))
      # Group::Root::Admin carries :finance, so its tiers end at the write tier.
      expect(tiers).to eq([
        [tier(:finance_read), false, "/session_settings?max_finance_permission=finance_read"],
        [tier(:finance_audit), false, "/session_settings?max_finance_permission=finance_audit"],
        ["#{tier(:finance)} (nach Rolle)", true, "/session_settings?max_finance_permission="]
      ])
      expect(bar_switches).to eq([["/session_settings?finance_tier_bar=always", false],
        ["/session_settings?finance_tier_bar=hidden", true]])
      expect(picker["data-provide"]).to eq("entity")
      expect(picker["data-url"]).to eq("/people/query?limit_by_permission=impersonate_user")
      expect(picker["data-wsjrdp-impersonate-url"]).to eq("/wsjrdp/impersonate")
      expect(picker["data-confirm"]).to include("%{person}")
      expect(tab.at_css("button[data-wsjrdp-session-action=delete]")).to be_nil
      expect(tab.css("a, [data-method]")).to be_empty
    end

    it "offers hiding instead of showing while the bar is up" do
      sign_in(admin)
      session[:compact_admin_tab] = "always"
      session[:finance_tier_bar] = "always"
      get :show, params: {id: booking.id}

      expect(bar_switches).to eq([["/session_settings?finance_tier_bar=always", true],
        ["/session_settings?finance_tier_bar=hidden", false]])
    end

    it "shows on demand while a bar is missing, and not with both bars up" do
      sign_in(admin)
      session[:compact_admin_tab] = "ondemand"
      get :show, params: {id: booking.id} # no impersonation, no yellow bar

      expect(tab).to be_present

      session[:max_finance_permission] = "finance_read" # the yellow bar, the red one missing
      get :show, params: {id: booking.id}

      expect(tab).to be_present
      expect(tiers.map(&:second)).to eq([true, false, false])

      session[:origin_user] = people(:cmt_leader).id # both bars, whoever impersonates
      get :show, params: {id: booking.id}

      expect(tab).to be_nil
    end

    it "goes by the person actually logged in: an admin impersonating the manager gets it, search and 'Imitation beenden'" do
      session[:origin_user] = admin.id
      session[:compact_admin_tab] = "ondemand"
      get :show, params: {id: booking.id}

      expect(tab).to be_present
      expect(picker).to be_present # the admin's right, not the manager's
      ending = tab.at_css("button.wsjrdp-admin-tab-end")
      expect(ending["data-wsjrdp-session-action"]).to eq("delete")
      expect(ending["data-url"]).to eq("/groups/#{manager.primary_group_id}/people/#{manager.id}/impersonate")
      expect(ending.text).to include(I18n.t("layouts.user_impersonation.end"))
      expect(tiers.map(&:first).last).to eq("#{tier(:finance_manage)} (nach Rolle)") # the manager's, not the admin's
    end

    it "is withheld from a non-admin impersonating, whoever they impersonate" do
      session[:origin_user] = people(:cmt_leader).id
      session[:compact_admin_tab] = "always"
      get :show, params: {id: booking.id}

      expect(tab).to be_nil
    end

    it "drops an unknown mode" do
      session[:compact_admin_tab] = "sometimes"
      get :show, params: {id: booking.id}

      expect(session[:compact_admin_tab]).to be_nil
      expect(controller.compact_admin_tab).to be_nil
    end
  end

  it "refuses a write the cap took away, in the controller too" do
    session[:max_finance_permission] = "finance_read"

    expect do
      patch :update, params: {id: booking.id, datev_booking: {sub_cost_center_number: "X1"}}
    end.to raise_error(CanCan::AccessDenied)
  end
end

# The session UI's background target.
describe SessionSettingsController, type: :controller do
  let(:person) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }

  before { sign_in(person) }

  it "stores a cap and answers without a body" do
    post :update, params: {max_finance_permission: "finance_read"}

    expect(response).to have_http_status(:no_content)
    expect(session[:max_finance_permission]).to eq("finance_read")
  end

  it "lifts it on an empty value" do
    session[:max_finance_permission] = "finance_read"
    post :update, params: {max_finance_permission: ""}

    expect(response).to have_http_status(:no_content)
    expect(session[:max_finance_permission]).to be_nil
  end

  it "stores the bar mode the same way" do
    post :update, params: {finance_tier_bar: "hidden"}

    expect(response).to have_http_status(:no_content)
    expect(session[:finance_tier_bar]).to eq("hidden")
  end

  it "stores the admin tab mode the same way" do
    post :update, params: {compact_admin_tab: "ondemand"}

    expect(response).to have_http_status(:no_content)
    expect(session[:compact_admin_tab]).to eq("ondemand")
  end
end

# The admin tab's person search: impersonate, or switch out of a running
# impersonation, always as the person who actually logged in.
describe Wsjrdp::ImpersonationController, type: :controller do
  let(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }
  let(:manager) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }
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

  it "does nothing for oneself or for the person already impersonated" do
    sign_in(admin)
    post :create, params: {person_id: admin.id}

    expect(response).to redirect_to(root_path)
    expect(session[:origin_user]).to be_nil

    sign_in(member)
    session[:origin_user] = admin.id
    post :create, params: {person_id: member.id}

    expect(session[:origin_user]).to eq(admin.id)
    expect(signed_in).to eq(member)
    expect(events(member)).to be_empty
  end
end
