# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Individuelle Ratenpläne tab of the Beiträge area: every person with an
# active or a planned individual plan, for the audit tier and up.
describe Fin::IndividualPaymentPlansController do
  render_views

  let(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }
  # yp: 17 x 200 € by direct debit, the fee (3.400 €) exactly.
  # other: 3.150 € by credit transfer, 250 € short of the fee; a planned plan too.
  # planner: a planned plan only, so the standard plan of the role (UL) shows.
  # reduced: an active rule with a reduction alone -- not listed.
  let(:yp) { people(:yp_a_1) }
  let(:other) { people(:yp_b_1) }
  let(:planner) { people(:ul_a_1) }
  let(:reduced) { people(:yp_a_2) }

  def rule(person, status, cents:, **attrs)
    Wsj27RdpFeeRule.create!(people_id: person.id, status: status, custom_installments_starting_year: 2026,
      custom_installments_cents: cents, **attrs)
  end

  before do
    # The migrated standard plans aside: the examples set up their own.
    WsjrdpPaymentPlan.kept.destroy_all
    WsjrdpPaymentPlan.create!(wsjrdp_role: "UL", single_payment: false, payment_method: "direct_debit",
      raw_installments_eur: [2025, *([0] * 11), 150, 350, 350, 350, 0, 0, 0, 0, 300, 0, 0, 300, 0, 0, 300, 0, 0, 300])
    active = rule(yp, "active", cents: [20_000] * 17, custom_installments_issue: "HELP-830",
      activated_at: Time.zone.local(2025, 11, 6, 21, 6))
    yp.update!(Wsjrdp2027::ParticipationFee.person_installments_attrs(active))
    transfer = rule(other, "active", cents: [*([0] * 10), 235_000, 0, 0, 40_000, 0, 0, 40_000],
      custom_installments_payment_method: "credit_transfer", custom_installments_issue: "HELP-1812",
      custom_installments_comment: "Zahlt selbst per Überweisung", activated_at: Time.zone.local(2026, 10, 1, 16))
    other.update!(Wsjrdp2027::ParticipationFee.person_installments_attrs(transfer))
    rule(other, "planned", cents: [*([15_000] * 12), 80_000, 0, 0, 80_000], custom_installments_issue: "HELP-2001",
      custom_installments_comment: "Ab 2027 Überweisung")
    rule(planner, "planned", cents: [20_000] * 17, custom_installments_issue: "HELP-1900")
    Wsj27RdpFeeRule.create!(people_id: reduced.id, status: "active", total_fee_reduction_cents: 170_000,
      activated_at: 1.day.ago)
  end

  def doc = Nokogiri::HTML(response.body)

  def entry(person, cents)
    AccountingEntry.create!(subject: person, author: finance, amount_cents: cents, description: "Beitrag",
      value_date: Date.new(2026, 2, 1), booking_date: Date.new(2026, 2, 1))
  end

  # A collection announced for the day (a pre-notification), nothing booked.
  def notification(person, collection_date, cents: 20_000)
    WsjrdpDirectDebitPreNotification.create!(payment_initiation: WsjrdpPaymentInitiation.create!, subject: person,
      author: finance, amount_cents: cents, description: "Einzug", dbtr_name: "Muster",
      dbtr_iban: "DE02120300000000202051", collection_date: collection_date, payment_status: "xml_generated")
  end

  def row_of(person) = doc.css("#main tbody tr").find { |tr| tr.text.include?(person.short_full_name_with_nickname) }

  def columns_of(tr) = tr.css("td").map { |td| td["class"].to_s[/ipcol-(\w+)/, 1] }

  # A cell's text without its tooltips (Nokogiri reads a template's content).
  def visible(node) = node.dup.tap { |copy| copy.css("template").remove }.text.squish

  it "refuses the read tier" do
    sign_in(reader)

    expect { get :index }.to raise_error(CanCan::AccessDenied)
    expect { post :apply }.to raise_error(CanCan::AccessDenied)
  end

  it "lists the people with an active or a planned plan, with the agreed columns" do
    sign_in(finance)
    get :index

    expect(response).to be_successful
    expect(doc.at_css("#main h1").text).to eq "Individuelle Ratenpläne"
    expect(doc.css("#main thead th.exp-col").map { |th| th["class"][/ipcol-(\w+)/, 1] })
      .to eq(%w[planned activated_at name role status paid total plan payment_method issue comment link])
    expect(doc.at_css("#main thead th.ipcol-planned i.fa-clock")).to be_present
    expect(doc.at_css("#main thead th.ipcol-payment_method i.fa-file-signature")["aria-label"]).to eq "Zahlungsart"
    expect(doc.at_css("#main thead th.ipcol-payment_method")["title"]).to eq "Zahlungsart"
    # The menu: the shown columns, then the hidden ones.
    expect(doc.css(".exp-cols-list .exp-cols-col label").map { |label| label.text.squish })
      .to eq(["Geplant", "Aktiviert", "Person", "Rolle", "Status", "bezahlt", "Gesamt", "Ratenplan", "Zahlungsart",
        "Vorgang", "Kommentar", "Person-id", "Beginn", "Ende", "Anzahl Raten", "Beitrag", "offen"])
    # The link to the Beitrag page: the last column, not in the menu, not on a
    # phone (the widget's `mobile: false`).
    expect(doc.at_css("#main thead th.ipcol-link")["class"]).to include("exp-no-mobile")
    expect(doc.css("#main table colgroup col").last["class"]).to eq "exp-no-mobile"
    expect(doc.css("#main thead th.exp-no-mobile, #main table colgroup col.exp-no-mobile").size).to eq 2
    expect(doc.css("#main tbody tr.exp-row").map { |tr| tr.at_css("td.ipcol-name").text.strip })
      .to eq([other, yp, planner].map(&:short_full_name_with_nickname))
    expect(row_of(reduced)).to be_nil
    expect(doc.at_css("select[aria-label='Einträge pro Seite'] option[selected]").text).to eq "100"
    expect(response.body).to include("3 Personen")
  end

  it "shows a plan as a strip of months with its figures, the sum checked against the fee" do
    sign_in(finance)
    get :index

    row = row_of(yp)
    expect(visible(row.at_css("td.ipcol-activated_at"))).to eq "06.11.25"
    expect(Nokogiri::HTML(row.at_css("td.ipcol-activated_at template").inner_html).text.squish)
      .to eq "Aktiviert am: Donnerstag, 06. November 2025 Uhrzeit: 21:06 Uhr"
    expect(row.at_css("td.ipcol-payment_method i")["class"]).to eq "fas fa-file-signature ipl-direct-debit"
    # The strip spans December 2025 to May 2027, the standard plans' span,
    # for a plan within it.
    bars = row.css("td.ipcol-plan .ipl-strip > .ipl-month")
    expect(bars.size).to eq 18
    expect(bars.first["data-ym"]).to eq "2025-12"
    expect(bars.last["data-ym"]).to eq "2027-05"
    expect(doc.css("#main table colgroup col")[7]["style"]).to eq "width: calc(10.625rem + var(--exp-g))"
    expect(bars.count { |month| !month.at_css(".ipl-bar")["class"].include?("ipl-zero") }).to eq 17
    expect(bars.first.at_css(".ipl-bar")["style"]).to eq "height: 1px"
    expect(bars.find { |month| month["data-ym"] == "2026-01" }.at_css(".ipl-bar")["style"]).to eq "height: 5px"
    expect(bars.find { |bar| bar["data-ym"] == "2026-01" }["data-label"]).to eq "Jan 2026: 200 €"
    expect(bars.find { |bar| bar["data-ym"] == "2025-12" }["data-label"]).to eq "Dez 2025: 0 €"
    expect(row.css("td.ipcol-plan .ipl-marks i").map(&:text)).to eq %w[26 27]
    tip = Nokogiri::HTML(row.at_css("td.ipcol-plan template.wsjrdp-tip").inner_html)
    expect(tip.at_css(".ipl-tip-head").text.squish).to eq "Ratenplan Summe 3.400 € · 17 Raten"
    expect(tip.css(".ipl-tip-table th").map(&:text)).to eq ["Zeitpunkt", "Betrag", "Soll Kontostand"]
    expect(tip.css(".ipl-tip-table tbody tr").first.css("td").map(&:text)).to eq ["Jan 2026", "200 €", "200 €"]
    expect(tip.css(".ipl-tip-table tbody tr").last.css("td").map(&:text)).to eq ["Mai 2027", "200 €", "3.400 €"]
    expect(visible(row.at_css("td.ipcol-total"))).to eq "3.400 €"
    expect(row.at_css("td.ipcol-total i")).to be_nil
    expect(row.at_css("td.exp-merged .ipl-notes-head").text).to eq "HELP-830"
    links = row.css("td.ipcol-link a")
    expect(links.pluck("href")).to eq [person_fee_path(yp)] * 2
    expect(links.first["class"]).to eq "text-muted"
    expect(links.first.at_css("i.fa-money-bill")).to be_present
    expect(links.last["target"]).to eq "_blank"
    expect(row.at_css("td.ipcol-link")["class"]).to include("exp-no-mobile")
    expect(row.next_element&.matches?("tr.exp-sub-row")).to be_falsey
  end

  it "marks a plan that does not cover the fee, and shows the planned plan under the active one" do
    sign_in(finance)
    get :index

    row = row_of(other)
    expect(row.at_css("td.ipcol-payment_method i")["class"]).to eq "fas fa-landmark ipl-credit-transfer"
    expect(visible(row.at_css("td.ipcol-total"))).to eq "3.150 €"
    expect(row.at_css("td.ipcol-total i")["class"]).to include("fa-exclamation-triangle").and include("text-danger")
    expect(Nokogiri::HTML(row.at_css("td.ipcol-total template").inner_html).text.squish)
      .to eq "Der Ratenplan deckt den Beitrag nicht: es fehlen 250 €."
    expect(row.at_css("td.exp-merged .ipl-notes-head").text).to eq "HELP-1812"
    expect(row.at_css("td.exp-merged .ipl-comment").text).to eq "Zahlt selbst per Überweisung"
    expect(Nokogiri::HTML(row.at_css("td.exp-merged template").inner_html).css("div").map { |line| line.text.squish })
      .to eq ["Vorgang: HELP-1812", "Kommentar: Zahlt selbst per Überweisung"]
    plan_line = row.next_element
    expect(plan_line["class"]).to include("exp-sub-row")
    expect(plan_line.at_css("td.ipcol-planned [title]")["title"])
      .to eq "Geplanter, noch nicht aktivierter Ratenplan: 3.400 €"
    expect(visible(plan_line.at_css("td.ipcol-activated_at"))).to eq "geplant"
    expect(plan_line.at_css("td.ipcol-payment_method i")["class"]).to eq "fas fa-file-signature ipl-direct-debit ipl-light"
    expect(plan_line.css("td.ipcol-plan .ipl-bar.ipl-planned").size).to eq 18
    expect(plan_line.css("td.ipcol-plan .ipl-bar.ipl-planned:not(.ipl-zero)").size).to eq 14
    expect(visible(plan_line.at_css("td.ipcol-total"))).to eq "3.400 €"
    expect(plan_line.at_css("td.exp-merged .ipl-draft-notes").text).to eq "HELP-2001 · Ab 2027 Überweisung"
    expect(Nokogiri::HTML(plan_line.at_css("td.ipcol-plan template.wsjrdp-tip").inner_html).at_css(".ipl-tip-head").text.squish)
      .to eq "Geplanter Ratenplan Summe 3.400 € · 14 Raten"
  end

  it "shows the standard plan of the role, named, while only a planned plan exists" do
    sign_in(finance)
    get :index

    row = row_of(planner)
    expect(row.at_css("td.ipcol-activated_at .muted.fw-light").text).to eq "noch nicht"
    expect(row.at_css("td.ipcol-planned i")).to be_nil
    expect(row.css("td.ipcol-plan .ipl-bar.ipl-standard:not(.ipl-zero)").size).to eq 8
    expect(row.at_css("td.ipcol-plan .ipl-standard-chip").text).to eq "Standard UL"
    tip = Nokogiri::HTML(row.at_css("td.ipcol-plan template.wsjrdp-tip").inner_html)
    expect(tip.at_css(".ipl-tip-head").text.squish).to eq "Standard-Ratenplan UL Summe 2.400 € · 8 Raten"
    expect(tip.at_css(".ipl-tip-foot").text).to eq "Gilt, solange kein individueller Ratenplan aktiv ist."
    expect(row.at_css("td.ipcol-total .muted").text).to eq "2.400 €"
    expect(row.at_css("td.ipcol-total i")).to be_nil
    expect(visible(row.at_css("td.exp-merged"))).to eq ""
    plan_line = row.next_element
    expect(plan_line["class"]).to include("exp-sub-row")
    expect(plan_line.at_css("td.exp-merged .ipl-draft-notes").text).to eq "HELP-1900"
  end

  it "widens the strip's column to the longest plan of the whole list, whatever the filter shows" do
    # A plan to August 2027: three months beyond the span, 21 bars.
    long = rule(people(:ul_a_2), "active", cents: [*([0] * 10), 1000, *([0] * 8), 1000],
      activated_at: Time.zone.local(2026, 5, 1, 12))
    people(:ul_a_2).update!(Wsjrdp2027::ParticipationFee.person_installments_attrs(long))
    sign_in(finance)
    get :index, params: {f: "!(!(!(pm,in,'credit_transfer')))"}

    expect(row_of(people(:ul_a_2))).to be_nil
    expect(row_of(other).css("td.ipcol-plan .ipl-strip > .ipl-month").size).to eq 18
    expect(doc.css("#main table colgroup col")[7]["style"]).to eq "width: calc(12.3125rem + var(--exp-g))"
    get :index

    expect(row_of(people(:ul_a_2)).css("td.ipcol-plan .ipl-strip > .ipl-month").size).to eq 21
    expect(row_of(people(:ul_a_2)).css("td.ipcol-plan .ipl-month").last["data-ym"]).to eq "2027-08"
  end

  it "shows a plan that starts and ends early from its start on, without a mark for a single month of a year" do
    # A single payment in August 2025: the strip runs to January 2027, the
    # standard span's length -- January alone gets no "27".
    early = Wsj27RdpFeeRule.create!(people_id: people(:ul_a_2).id, status: "active",
      custom_installments_starting_year: 2025, custom_installments_cents: [*([0] * 7), 340_000],
      activated_at: Time.zone.local(2025, 8, 1, 12))
    people(:ul_a_2).update!(Wsjrdp2027::ParticipationFee.person_installments_attrs(early))
    sign_in(finance)
    get :index

    bars = row_of(people(:ul_a_2)).css("td.ipcol-plan .ipl-strip > .ipl-month")
    expect(bars.pluck("data-ym").values_at(0, -1)).to eq %w[2025-08 2027-01]
    expect(bars.size).to eq 18
    expect(row_of(people(:ul_a_2)).css("td.ipcol-plan .ipl-marks i").map(&:text)).to eq %w[26]
    expect(row_of(yp).css("td.ipcol-plan .ipl-marks i").map(&:text)).to eq %w[26 27]
  end

  it "colours what came in by its state, flags arrears and late entries, and names what is due" do
    travel_to(Time.zone.local(2026, 10, 8, 12)) do
      # yp, direct debit from January: nine months due, nothing came in --
      # behind; one collection announced for September.
      notification(yp, Date.new(2026, 9, 7))
      # other, credit transfer from November: nothing due yet, more than the
      # fee came in -- overpaid. planner, a planned plan alone: the fee
      # exactly, but not judged; one entry dated after the end of the month.
      entry(other, 350_000)
      entry(planner, 340_000)
      AccountingEntry.create!(subject: planner, author: finance, amount_cents: 10_000, description: "Beitrag",
        value_date: Date.new(2026, 11, 3), booking_date: Date.new(2026, 11, 3))
      sign_in(finance)
      get :index

      expect(row_of(yp).at_css("td.ipcol-paid .ipl-paid-behind").text).to eq "0 €"
      expect(row_of(yp).css("td.ipcol-paid .ipl-flag i").pluck("class"))
        .to eq ["fas fa-exclamation-triangle text-danger"]
      tip = Nokogiri::HTML(row_of(yp).at_css("td.ipcol-paid template").inner_html).css("div").map { |l| l.text.squish }
      expect(tip).to eq ["Bezahlt: 0 €", "Beitrag: 3.400 €",
        "Fällig bis heute: 1.800 € – ohne Rate Okt 2026",
        "In Verzug: es fehlen 1.800 €."]
      expect(row_of(other).at_css("td.ipcol-paid .ipl-paid-over").text).to eq "3.500 €"
      tip = Nokogiri::HTML(row_of(other).at_css("td.ipcol-paid template").inner_html).css("div").map { |l| l.text.squish }
      expect(tip).to eq ["Bezahlt: 3.500 €", "Beitrag: 3.400 €",
        "Fällig bis heute: 0 €", "Überbezahlt um 100 €."]
      expect(row_of(other).at_css("td.ipcol-paid i")).to be_nil
      expect(row_of(planner).at_css("td.ipcol-paid .wsjrdp-tip-host > span")["class"]).to be_nil
      expect(row_of(planner).css("td.ipcol-paid i").pluck("class")).to eq ["fas fa-hourglass-half ipl-late"]
      expect(Nokogiri::HTML(row_of(planner).at_css("td.ipcol-paid template").inner_html).css("div").map { |l| l.text.squish })
        .to eq ["Bezahlt: 3.500 €", "Beitrag: 3.400 €", "Kein aktiver Ratenplan: kein Soll.",
          "Valuta nach Monatsende: 03.11.2026: 100 € – Beitrag"]
    end
  end

  it "offers the hidden figures of the plan and the balance in the columns menu" do
    sign_in(finance)
    get :index, params: {c: "at,nm,bg,en,ct,tt,fe,pd,op"}

    expect(columns_of(row_of(yp))).to eq %w[activated_at name begin end count total fee paid open link]
    expect(row_of(yp).at_css("td.ipcol-fee .muted").text).to eq "3.400 €"
    expect(row_of(yp).css("td.ipcol-begin, td.ipcol-end, td.ipcol-count").map { |td| td.text.squish })
      .to eq ["01/26", "05/27", "17"]
    expect(row_of(yp).css("td.ipcol-paid, td.ipcol-open").map { |td| visible(td) })
      .to eq ["0 €", "3.400 €"]
    expect(row_of(planner).css("td.ipcol-begin .muted, td.ipcol-end .muted, td.ipcol-count .muted").map(&:text))
      .to eq ["12/25", "05/27", "8"]
    expect(row_of(planner).next_element.css("td.ipcol-begin, td.ipcol-end, td.ipcol-count").map { |td| td.text.squish })
      .to eq ["01/26", "05/27", "17"]
  end

  describe "the quick filters" do
    before { sign_in(finance) }

    def shown(filter)
      get :index, params: {f: filter}
      [yp, other, planner].select { |person| row_of(person) }
    end

    it "offers four exclusive groups, the unrestricted asterisk in front of each" do
      get :index

      groups = doc.css(".flt-presets .flt-segment").map { |g| g.css("a").map { |a| a.text.strip } }
      expect(groups).to eq([["", "geplant", "ohne Plan"], ["", "bestätigt", "nicht bestätigt"],
        ["", "Lastschrift", "Überweisung"], ["", "Plan ≠ Beitrag"], ["", "in Verzug"]])
      expect(doc.css(".flt-presets .flt-segment a i").pluck("class").reject { |css| css.include?("asterisk") })
        .to eq ["fas fa-clock", "fas fa-file-signature", "fas fa-landmark", "fas fa-exclamation-triangle"]
    end

    it "narrows by plan, payment method and the check against the fee" do
      expect(shown("!(!(!(pl,in,'ja')))")).to eq [other, planner]
      expect(shown("!(!(!(pl,in,'nein')))")).to eq [yp]
      expect(shown("!(!(!(pm,in,'credit_transfer')))")).to eq [other]
      expect(shown("!(!(!(pm,in,'direct_debit')))")).to eq [yp]
      expect(shown("!(!(!(mm,in,'ja')))")).to eq [other]
    end

    it "narrows to the people behind, as of today" do
      travel_to(Time.zone.local(2026, 10, 8, 12)) do
        expect(shown("!(!(!(vz,in,'ja')))")).to eq [yp]
        expect(shown("!(!(!(vz,in,'nein')))")).to eq [other, planner]
        entry(yp, 180_000)

        expect(shown("!(!(!(vz,in,'ja')))")).to eq []
      end
    end

    it "applies the filter builder's form and comes back to the page" do
      post :apply, params: {filter_json: [[["planned", "in", "ja"]]].to_json}

      expect(response).to have_http_status(:see_other)
      expect(CGI.unescape(response.location)).to end_with("/fin/individual_payment_plans?f=!(!(!(pl,in,'ja')))")
    end
  end
end
