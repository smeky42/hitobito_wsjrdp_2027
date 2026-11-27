# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The session UI: a red bar while impersonating, a yellow one that is the
# tier selection, and the admin tab. Every action is a background button.
describe "layouts/_wsjrdp_session_bar" do
  before_all(setup_fixtures: true) {}

  let_it_be(:manager) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }
  let_it_be(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }

  def all_tiers = %w[finance_none finance_read finance_audit finance finance_manage]

  def render_bar(person: manager, pick: nil, origin: nil, bar: :ondemand, tab: :hidden)
    ability = Ability.new(person, max_finance_permission: pick)
    session[:origin_user] = origin&.id
    without_partial_double_verification do
      allow(view).to receive_messages(current_ability: ability, current_user: person, origin_user: origin,
        max_finance_permission: pick, finance_tier_bar: bar, admin_tab: tab)
      allow(view).to receive(:can?) { |*args| ability.can?(*args) }
    end
    render partial: "layouts/wsjrdp_session_bar"
    @doc = Nokogiri::HTML(rendered)
  end

  def bars = @doc.css(".wsjrdp-session-bar")

  def danger = @doc.at_css(".wsjrdp-session-bar .alert-danger")

  def warning = @doc.at_css(".wsjrdp-session-bar .alert-warning")

  def tab = @doc.at_css(".wsjrdp-admin-tab")

  def tier_url(tier) = "/session_settings?max_finance_permission=#{tier}"

  # [pressed?, url] per segment, in rank order.
  def segments = warning.css(".wsjrdp-seg button").map { |b| [b["aria-pressed"] == "true", b["data-url"]] }

  # [method, url query as a hash] of a bar's one action.
  def action(alert)
    button = alert.at_css("button.wsjrdp-bar-action")
    [button["data-wsjrdp-session-action"], Rack::Utils.parse_query(URI(button["data-url"]).query)]
  end

  def logo_offset = rendered[/header\.logo \{ margin-top: (\d+)px; \}/, 1]&.to_i

  def impersonate_path(person) = "/groups/#{person.primary_group_id}/people/#{person.id}/impersonate"

  describe "the bars" do
    it "shows nothing without a cap, an impersonation or the tab" do
      render_bar

      expect(rendered).to be_blank
    end

    it "offers every tier up to the roles' own, the one in force pressed, and a reset to the default" do
      render_bar(pick: :finance_audit)

      expect(bars.size).to eq(1)
      expect(danger).to be_nil
      expect(segments).to eq(all_tiers.map { |tier| [tier == "finance_audit", tier_url(tier)] })
      expect(action(warning)).to eq(["post", {"max_finance_permission" => "", "finance_tier_bar" => "ondemand"}])
      expect(warning.css("a, [data-method]")).to be_empty
    end

    it "shows an elevated tier in red" do
      render_bar(pick: :finance_manage, bar: :hidden)

      expect(warning).to be_nil
      expect(danger.css(".wsjrdp-seg button[aria-pressed=true]").pluck("data-url"))
        .to eq([tier_url(:finance_manage)])
    end

    it "presses the default, not the ceiling, with the bar always shown" do
      render_bar(bar: :always)

      expect(segments.map(&:first)).to eq([false, false, false, true, false])
    end

    it "stacks the red and the yellow bar while impersonating with a cap, the logo clearing both" do
      render_bar(origin: people(:cmt_leader), pick: :finance_read)

      expect(bars.size).to eq(2)
      expect(bars.first.at_css(".alert-danger")).to be_present
      expect(action(danger)).to eq(["delete", {}])
      expect(danger.at_css("button.wsjrdp-bar-action")["data-url"]).to eq(impersonate_path(manager))
      expect(segments.map(&:first)).to eq([false, true, false, false, false])
      expect(logo_offset).to eq(60)
    end

    it "shows only the red bar while impersonating without a cap" do
      render_bar(origin: people(:cmt_leader))

      expect(bars.size).to eq(1)
      expect(warning).to be_nil
      expect(danger.css("button[data-wsjrdp-session-action]").size).to eq(1)
    end
  end

  describe "the admin tab" do
    def tiers = tab.css("button.wsjrdp-admin-tab-tier").map { |b| [b["aria-current"] == "true", b["data-url"]] }

    def default_tier = tab.css("button.wsjrdp-admin-tab-tier").find { _1.text.include?(I18n.t("layouts.wsjrdp_session_bar.tier_default")) }["data-url"]

    # [url, disabled?] of the show and the hide switch.
    def bar_switches
      %w[show hide].map { |kind|
        b = tab.at_css("button.wsjrdp-admin-tab-bar-#{kind}")
        [b["data-url"], b["disabled"].present?]
      }
    end

    def picker = tab.at_css("input[data-wsjrdp-impersonate-url]")

    def go = tab.at_css("[data-wsjrdp-impersonate=go]")

    it "offers an admin the tiers, the bar switches and the person search" do
      render_bar(person: admin, tab: :always)

      # Group::Root::Admin carries :finance, so its tiers end at the write tier.
      expect(tiers).to eq(all_tiers.first(4).map { |tier| [tier == "finance", tier_url(tier)] })
      expect(default_tier).to eq(tier_url(:finance))
      expect(tab.at_css("button.wsjrdp-admin-tab-reset")["disabled"]).to be_present # nothing picked yet
      expect(bar_switches).to eq([["/session_settings?finance_tier_bar=always", false],
        ["/session_settings?finance_tier_bar=hidden", true]])
      expect(picker["data-url"]).to eq("/wsjrdp/impersonate/people")
      expect(picker["data-wsjrdp-impersonate-url"]).to eq("/wsjrdp/impersonate")
      confirm = tab.at_css(".wsjrdp-admin-tab-confirm")
      expect(confirm.key?("hidden")).to be(true)
      expect(Settings.impersonate.notify).to be(true)
      expect(confirm.at_css(".wsjrdp-admin-tab-confirm-notice")).to be_present
      expect(go["disabled"]).to be_present
      expect(go["data-countdown-ms"]).to eq(WsjrdpAdminTabHelper::DEFAULT_IMPERSONATE_DELAY_MS.to_s)
      expect(tab.at_css("button[data-wsjrdp-session-action=delete]")).to be_nil
      expect(tab.css("a, [data-method]")).to be_empty
    end

    it "offers hiding and the reset while the bar is up with a pick" do
      render_bar(person: admin, tab: :always, pick: :finance_read)

      expect(bar_switches).to eq([["/session_settings?finance_tier_bar=always", true],
        ["/session_settings?finance_tier_bar=hidden", false]])
      expect(tab.at_css("button.wsjrdp-admin-tab-reset")["disabled"]).to be_nil
      expect(tiers.map(&:first)).to eq([false, true, false, false])
    end

    it "leaves the impersonation button ready at once without a delay" do
      allow(view).to receive(:impersonate_delay_ms).and_return(0)
      render_bar(person: admin, tab: :always)

      expect(go["data-countdown-ms"]).to eq("0")
      expect(go["disabled"]).to be_nil
    end

    it "goes by the person actually logged in: an admin impersonating the manager gets the search and the end" do
      render_bar(origin: admin, tab: :ondemand)

      expect(picker).to be_present # the admin's right, not the manager's
      ending = tab.at_css("button.wsjrdp-admin-tab-end")
      expect(ending["data-wsjrdp-session-action"]).to eq("delete")
      expect(ending["data-url"]).to eq(impersonate_path(manager))
      # the manager's ceiling and default, not the admin's
      expect(tiers.map(&:second)).to eq(all_tiers.map { tier_url(_1) })
      expect(default_tier).to eq(tier_url(:finance))
    end

    it "is withheld from a manager without :admin" do
      render_bar(tab: :always)

      expect(tab).to be_nil
    end

    it "is withheld from a non-admin impersonating" do
      render_bar(origin: people(:cmt_leader), tab: :always)

      expect(tab).to be_nil
    end
  end
end
