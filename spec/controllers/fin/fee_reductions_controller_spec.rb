# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Reduktionen tab of the Beiträge area: every person with an active or a
# planned total fee reduction, for the audit tier and up; a row opens into the
# "Beitragshöhe" view of the person without its buttons.
describe Fin::FeeReductionsController do
  render_views

  let(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }
  let(:yp) { people(:yp_a_1) }
  let(:other) { people(:yp_b_1) }
  let(:planner) { people(:ul_a_1) }

  before do
    # The detail shows the installments, which the test database only has as
    # a custom plan.
    [yp, other, planner].each do |person|
      Wsj27RdpFeeRule.create!(people_id: person.id, status: "active", activated_at: 1.day.ago,
        custom_installments_starting_year: 2026, custom_installments_cents: [100_000])
    end
    yp.update!(wsjrdp_total_fee_reduction: 250, wsjrdp_total_fee_reduction_hint: "Härtefall",
      wsjrdp_total_fee_reduction_issue: "HELP-123", wsjrdp_total_fee_reduction_comment: "Nachweis liegt vor")
    planner.update!(planned_total_fee_reduction: "400")
  end

  def doc = Nokogiri::HTML(response.body)

  def row_of(person) = doc.css("#main tbody tr").find { |tr| tr.text.include?(person.short_full_name_with_nickname) }

  it "lists the people with an active or a planned reduction, with the agreed columns" do
    sign_in(finance)
    get :index

    expect(response).to be_successful
    headers = doc.css("#main thead th.exp-col").map { |th| th.text.gsub(/[↑↓⇅]/, "").strip }
    expect(headers).to eq(["", "Aktiviert", "Person", "Rolle", "Status", "Hinweis", "Kommentar", "Vorgang",
      "regulär", "Reduktion", "reduziert"])
    expect(doc.at_css("#main thead th.frcol-planned i.fa-clock")).to be_present
    expect(doc.at_css(".exp-cols-list .exp-cols-col label").to_html).to include("fa-clock").and include("Geplant")
    # "Beitrag" over a bracket spanning exactly the calculation, in the second
    # header row; every other header spans both rows.
    expect(doc.at_css("#main thead th.exp-col-group[colspan='3'] .exp-col-group-bracket").text.strip).to eq "Beitrag"
    expect(doc.css("#main thead tr").last.css("th").map { |th| th.text.gsub(/[↑↓⇅]/, "").strip })
      .to eq(%w[regulär Reduktion reduziert])
    expect(doc.css("#main thead th.exp-col[rowspan='2']").size).to eq 8
    # Growing gaps: after every column but the clock (next to its date), the
    # members of the fee group and the last column; up to the widget's default
    # each, and filter and toolbar stop where the table stops.
    gapped = row_of(yp).css("td.exp-gap").map { |td| td["class"][/frcol-(\w+)/, 1] }
    expect(gapped).to eq(%w[activated_at name role status reduced_fee])
    table_style = doc.at_css("#main table.bookings-table")["style"]
    # Person and notes widen first (--exp-c, up to 2rem per unit of `grow:`),
    # only then the gaps (--exp-g, up to 4rem).
    expect(table_style).to include("--exp-c: clamp(0px, round(down, (100cqw - 62.25rem) / 5.0, 1px), 2rem)")
      .and include("--exp-g: clamp(0px, round(down, ((100cqw - 62.25rem) - 5.0 * var(--exp-c)) / 5, 1px), 4rem)")
    expect(doc.css("#main table colgroup col")[2]["style"])
      .to eq "width: calc(10.25rem + var(--exp-g) + 2.0 * var(--exp-c))"
    expect(doc.css("#main table colgroup col")[1]["style"]).to eq "width: calc(5.25rem + var(--exp-g))"
    expect(doc.css("#main table colgroup col")[5]["style"]).to eq "width: 4.75rem"
    expect(doc.at_css(".bk-select-scope")["style"]).to eq "max-width: calc(62.25rem + 5.0 * 2rem + 5 * 4rem)"
    expect(doc.at_css(".exp-filter-limit")["style"]).to eq "max-width: calc(62.25rem + 5.0 * 2rem + 5 * 4rem)"
    expect(row_of(yp).css("td.exp-tnum").map { |td| td["class"][/frcol-(\w+)/, 1] })
      .to eq(%w[activated_at regular_fee reduction reduced_fee])
    expect(row_of(yp).css("td.frcol-regular_fee, td.frcol-reduction, td.frcol-reduced_fee").map { |td| td.text.squish })
      .to eq(["3.400 €", "−250 €", "=3.150 €"])
    titles = doc.css("#main thead th[title]").to_h { |th| [th.text.gsub(/[↑↓⇅]/, "").strip, th["title"]] }
    expect(titles).to eq("Hinweis" => "Kurzhinweis, wird im Vertrag angezeigt", "Vorgang" => "Helpdesk-Vorgang",
      "Kommentar" => "Nur für Personen mit Buchhaltungs-Rechten")
    # The fixed layout takes its widths from the colgroup, not from the group row.
    expect(doc.css("#main table colgroup col").first["style"]).to eq "width: 1.25rem"
    expect(row_of(yp).text).to include("250 €").and include("Härtefall").and include("HELP-123")
    expect(row_of(yp).text).not_to include(",—")
    plan_line = row_of(planner).next_element
    expect(plan_line["class"]).to include("exp-sub-row")
    expect(plan_line.at_css("td.frcol-planned [title^='Geplante, noch nicht aktivierte Reduktion: 400 €']")).to be_present
    expect(row_of(planner).at_css("td.frcol-planned i")).to be_nil
    expect(row_of(planner).at_css("td.frcol-activated_at .muted.fw-light").text).to eq "noch nicht"
    expect(row_of(other)).to be_nil
  end

  it "keeps the fee columns together under their group in the columns menu, named in one line" do
    sign_in(finance)
    get :index

    group = doc.at_css(".exp-cols-list .exp-cols-group")
    expect(group.text.squish).to eq "⠿ Beitrag Beitrag regulär Reduktion Beitrag reduziert"
    expect(group.css(".exp-cols-col").pluck("data-abbr")).to eq %w[rf red fee]
  end

  it "orders by the activation, oldest first, a plan alone after all" do
    with_versioning do
      PaperTrail.request(whodunnit: finance.id.to_s) { yp.update!(wsjrdp_total_fee_reduction: 300) }
    end
    other.update!(wsjrdp_total_fee_reduction: 100)
    sign_in(finance)
    get :index

    names = doc.css("#main tbody tr").map { |tr| tr.at_css("td.frcol-name")&.text&.strip }.compact
    expect(names.index(planner.short_full_name_with_nickname)).to be > names.index(yp.short_full_name_with_nickname)
  end

  it "shows the roles as badges in their colours, the regular fee and the usual status muted" do
    yp.update!(status: "confirmed")
    sign_in(finance)
    get :index

    badges = row_of(yp).css("td.frcol-role .wsjrdp-tip-host > .wsjrdp-role")
    expect(badges.map(&:text)).to eq(%w[YP])
    expect(badges.first["class"]).to include("wsjrdp-role-yp")
    expect(response.body.scan(".wsjrdp-role-yp {").size).to eq 1
    expect(row_of(yp).at_css("td.frcol-regular_fee .muted").text).to eq "3.400 €"
    status = row_of(yp).at_css("td.frcol-status .wsjrdp-tip-host")
    expect(status.at_css("> span.fee-reduction-status-confirmed").text).to eq "bestätigt"
    expect(Nokogiri::HTML(status.at_css("template").inner_html).text.squish).to eq "Status: Bestätigt durch CMT"
  end

  it "shows both roles where they differ, the contingent's first, both named in the tooltip" do
    yp.update!(wsj_role: "IST")
    sign_in(finance)
    get :index

    pair = row_of(yp).at_css("td.frcol-role .wsjrdp-role-pair .wsjrdp-tip-host")
    expect(pair.css("> .wsjrdp-role").map(&:text)).to eq(%w[YP IST])
    tip = Nokogiri::HTML(pair.at_css("template.wsjrdp-tip").inner_html)
    expect(tip.css("div").map { |line| line.text.squish }).to eq(["Rolle im Kontingent: YP", "Rolle auf dem Jamboree: IST"])
    expect(tip.css(".wsjrdp-role").pluck("class")).to eq(["wsjrdp-role wsjrdp-role-yp", "wsjrdp-role wsjrdp-role-ist"])
  end

  it "dates the activation from the person log, with time and author as the tooltip" do
    with_versioning do
      PaperTrail.request(whodunnit: finance.id.to_s) { yp.update!(wsjrdp_total_fee_reduction: 300) }
    end
    sign_in(finance)
    get :index

    host = row_of(yp).at_css("td.frcol-activated_at .wsjrdp-tip-host")
    expect(host.at_css("> span").text).to eq Time.zone.today.strftime("%d.%m.%y")
    lines = Nokogiri::HTML(host.at_css("template").inner_html).css("div").map { |d| d.text.squish }
    expect(lines.first).to eq "Aktiviert am: #{I18n.l(Time.zone.today, format: "%A, %d. %B %Y")}"
    expect(lines.second).to match(/\AUhrzeit: \d\d:\d\d Uhr\z/)
    expect(lines.third).to eq "von: #{finance}"
  end

  it "opens a row into the Beitragshöhe view, with the comment and the buttons but without heading" do
    sign_in(finance)
    get :index

    section = doc.css("section.fee-reduction").find { |el| el.text.include?("Härtefall") }
    expect(section.text).to include("Reduzierter Beitrag").and include("Nachweis liegt vor")
    expect(section.at_css("h2")).to be_nil
    actions = doc.at_css("#fee_reduction_actions_#{yp.id}")
    expect(actions.text).to include("Neue Reduktion planen").and include("Aus aktueller Reduktion planen")
    expect(doc.css("[id^='fee_reduction_actions_']").size).to eq 2
    # A change in a row reloads the page (reload_keep_scroll), the action ships
    # with the page.
    expect(response.body).to include("hitobito_wsjrdp_2027/turbo_stream_actions")
    expect(doc.at_css(".exp-detail-links").text).to include("Beitrags-Seite der Person")
    expect(response.body).to include(person_fee_path(yp))
  end

  it "shows the plan of a person without an active reduction in the row's view" do
    sign_in(finance)
    get :index

    section = doc.css("section.fee-reduction").find { |el| el.text.include?("Geplant: Reduktion 400") }
    expect(section).to be_present
  end

  it "offers no buttons to the audit tier, who may not change the fee" do
    auditor = Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: Fabricate(Group::Extern.name.to_sym, parent: groups(:root))).person
    sign_in(auditor)
    get :index

    expect(doc.css("section.fee-reduction")).to be_present
    expect(doc.css("[id^='fee_reduction_actions_']")).to be_empty
  end

  describe "quick filters" do
    before do
      yp.update!(status: "confirmed")
      sign_in(finance)
    end

    def shown(filter)
      get :index, params: {f: filter}
      [yp, planner].select { |person| row_of(person) }
    end

    it "offers two exclusive groups, the unrestricted asterisk in front of each" do
      get :index

      groups = doc.css(".flt-presets .flt-segment").map { |g| g.css("a").map { |a| a.text.strip } }
      expect(groups).to eq([["", "geplant", "ohne Plan"], ["", "bestätigt", "nicht bestätigt"]])
      expect(doc.css(".flt-presets .flt-segment a.flt-preset-icon-only").pluck("title"))
        .to eq(["ohne Einschränkung", "ohne Einschränkung"])
      expect(doc.at_css(".flt-presets .flt-segment a i.fa-clock")).to be_present
    end

    it "narrows to planned or unplanned reductions" do
      expect(shown("!(!(!(pl,in,'ja')))")).to eq [planner]
      expect(shown("!(!(!(pl,in,'nein')))")).to eq [yp]
    end

    it "searches names, hint and comment, the planned ones too" do
      planner.update!(planned_total_fee_reduction_comment: "Härtefall laut Antrag")

      expect(shown("!(!(!(q,contains,'Nachweis')))")).to eq [yp]
      expect(shown("!(!(!(q,contains,'laut Antrag')))")).to eq [planner]
      expect(shown("!(!(!(q,contains,'#{yp.first_name}')))")).to eq [yp]
    end

    it "narrows to confirmed or other people" do
      expect(shown("!(!(!(bs,in,'ja')))")).to eq [yp]
      expect(shown("!(!(!(bs,in,'nein')))")).to eq [planner]
    end
  end

  describe "hint, issue and comment" do
    before { sign_in(finance) }

    def notes(params = {})
      get :index, params: params
      row_of(yp).at_css("td.exp-merged")
    end

    it "share one cell under three sortable headers: hint left and issue right, the comment below" do
      cell = notes
      expect(cell["colspan"]).to eq "3"
      expect(cell.css(".fee-reduction-notes-head > *").map { |el| el.text.strip }).to eq(%w[Härtefall HELP-123])
      expect(cell.at_css(".wsjrdp-tip-host .fee-reduction-comment.fst-italic").text).to eq "Nachweis liegt vor"
      tip = Nokogiri::HTML(cell.at_css(".wsjrdp-tip-host > template").inner_html).css("div").map { |d| d.text.squish }
      expect(tip).to eq(["Hinweis: Härtefall", "Vorgang: HELP-123", "Kommentar: Nachweis liegt vor"])
      sortable = doc.css("#main thead th.frcol-hint a.exp-sort, #main thead th.frcol-issue a.exp-sort, " \
        "#main thead th.frcol-comment a.exp-sort")
      expect(sortable.size).to eq 3
      # In the columns menu one block, its parts only shown or hidden.
      block = doc.css(".exp-cols-list .exp-cols-group").find { |g| g.text.include?("Notizen") }
      expect(block.css(".exp-cols-col").pluck("data-abbr")).to eq %w[hi cm is]
      expect(block.css(".exp-cols-col[draggable]")).to be_empty
    end

    it "splits the merged width evenly and spreads the headers: first at the start, last at the end" do
      notes
      cols = doc.css("#main table colgroup col").pluck("style")
      expect(cols.last(3)).to eq(["width: calc(6.0625rem + 1.0 * var(--exp-c))",
        "width: calc(6.0625rem + 1.0 * var(--exp-c))", "width: calc(6.125rem + 1.0 * var(--exp-c))"])
      aligns = %w[hint comment issue].map { |k| doc.at_css("#main thead th.frcol-#{k}")["class"][/text-(start|center|end)/] }
      expect(aligns).to eq(%w[text-start text-center text-end])
    end

    it "leaves out the first line without hint and issue, and the comment without one" do
      yp.update!(wsjrdp_total_fee_reduction_hint: nil, wsjrdp_total_fee_reduction_issue: nil)
      expect(notes.at_css(".fee-reduction-notes-head")).to be_nil
      expect(notes.at_css(".fee-reduction-comment")).to be_present

      yp.update!(wsjrdp_total_fee_reduction_hint: "Härtefall", wsjrdp_total_fee_reduction_comment: nil)
      expect(notes.at_css(".fee-reduction-comment")).to be_nil
      expect(notes.at_css(".fee-reduction-notes-head").text.strip).to eq "Härtefall"
    end

    it "shows only the parts whose columns are shown" do
      cell = notes(c: "pl,at,nm,hi,cm")

      expect(cell["colspan"]).to eq "2"
      # What the cell shows -- the tooltip (a template) names all three anyway.
      shown = cell.css(".wsjrdp-tip-host > div").map { |d| d.text.squish }
      expect(shown).to eq(["Härtefall", "Nachweis liegt vor"])
    end

    it "has no comment lines with the comment hidden" do
      cell = notes(c: "pl,at,nm,hi,is")

      expect(cell.css(".fee-reduction-notes-head > *").map { |el| el.text.strip }).to eq(%w[Härtefall HELP-123])
      expect(cell.at_css(".fee-reduction-comment")).to be_nil
    end
  end

  it "shows a planned reduction as a muted sub-row under the cells it would replace" do
    planner.update!(planned_total_fee_reduction_hint: "Neu geplant", planned_total_fee_reduction_issue: "HELP-9",
      planned_total_fee_reduction_comment: "Erst ab Januar")
    sign_in(finance)
    get :index

    sub = doc.css("#main tr.exp-sub-row").find { |tr| tr.text.include?("Neu geplant") }
    cells = sub.css("td").to_h { |td| [td["class"][/frcol-(\w+)/, 1], td.text.squish] }.compact_blank
    expect(cells).to include("activated_at" => "geplant", "reduction" => "−400 €")
    expect(sub.at_css("td.frcol-hint > div > .wsjrdp-tip-host > .fee-reduction-plan-notes").text).to eq "Neu geplant · HELP-9"
    expect(sub.at_css("td.frcol-reduction div.muted.fw-light")).to be_present
    # One line; the planned comment only in the tooltip.
    expect(sub.css("td.frcol-hint .fee-reduction-plan-notes").size).to eq 1
    expect(sub.at_css(".fee-reduction-comment")).to be_nil
    tip = Nokogiri::HTML(sub.at_css(".wsjrdp-tip-host template").inner_html).text.squish
    expect(tip).to eq "Hinweis: Neu geplant Vorgang: HELP-9 Kommentar: Erst ab Januar"
    expect(row_of(yp).next_element&.matches?("tr.exp-sub-row")).to be_falsey
  end

  it "colours the status: confirmed green, a noted deregistration orange, a deregistration red" do
    {"confirmed" => "confirmed", "deregistration_noted" => "noted", "deregistered" => "deregistered"}.each do |status, css|
      yp.update!(status: status)
      sign_in(finance)
      get :index

      expect(row_of(yp).at_css("td.frcol-status .fee-reduction-status-#{css}")).to be_present
    end
  end

  it "is closed to the finance read tier" do
    sign_in(reader)

    expect { get :index }.to raise_error(CanCan::AccessDenied)
  end
end
