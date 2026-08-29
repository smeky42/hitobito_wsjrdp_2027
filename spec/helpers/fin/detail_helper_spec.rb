# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# What `= fin_detail(record, ctx) do |d| ... end` RENDERS: the three layouts,
# the blank modes, the help line and the tooltip, the page header, the raw
# blocks and the captured custom HTML.
#
# The record is unsaved and every value is invented -- names, IBANs and account
# numbers in this spec mean nothing.
describe Fin::DetailHelper do
  let(:account) do
    WsjrdpPersonalAccount.new(number: "700000", name: "Testkreditor",
      iban: "XX11TEST0000", description: "Beschreibungstext",
      datev_short_name: "TESTKRED")
  end

  let(:regular) { Fin::AttrFormatContext.regular }
  let(:embedded) do
    Fin::AttrFormatContext.embedded(Wsjrdp::TableContext.new(level: 1, lazy: true))
  end

  def detail(ctx = regular, **options, &block)
    Nokogiri::HTML.fragment(helper.fin_detail(account, ctx, **options, &block))
  end

  # Defines a formatter on the view context under test, for one example.
  def stub_helper(name, &block)
    helper.singleton_class.define_method(name, &block)
  end

  it "wraps the detail in the shared item-detail card" do
    doc = detail { |d| d.attrs :name }
    expect(doc.css(".bk-item-detail").size).to eq(1)
  end

  describe "the layouts" do
    it "renders the form-like grid list on the record's own page" do
      doc = detail { |d| d.attrs :name, :iban }
      dl = doc.at_css("dl.fin-detail-list")
      expect(dl).to be_present
      expect(dl.css(".row dt.col-md-3.col-xl-2.text-md-end.text-muted").map(&:text))
        .to eq(["Name", "IBAN"])
      expect(dl.css(".row dd.col-md-9.col-lg-8.col-xl-8.mw-63ch").map(&:text))
        .to eq(["Testkreditor", "XX11 TEST 0000"])
    end

    it "renders the compact rows in an embedded pane" do
      doc = detail(embedded) { |d| d.attrs :name, :iban }
      expect(doc.at_css("dl.fin-detail-list")).to be_nil
      dl = doc.at_css("dl.row.small")
      expect(dl.css("dt.col-sm-3").map(&:text)).to eq(["Name", "IBAN"])
      expect(dl.css("dd.col-sm-9").map(&:text)).to eq(["Testkreditor", "XX11 TEST 0000"])
    end

    it "renders the cells of the grid layout, with span and alignment" do
      doc = detail(layout: :grid) do |d|
        d.attrs :name, :description, description: {span: 2}, name: {align: :end}
      end
      cells = doc.css(".row.g-3 > div")
      expect(cells.map { |cell| cell.at_css(".booking-detail-label").text })
        .to eq(["Name", "Beschreibung"])
      expect(cells.first["class"]).to eq("col-6 col-md-4 col-lg-3")
      expect(cells.last["class"]).to eq("col-12 col-md-8 col-lg-6")
      expect(cells.first.at_css(".text-break")["class"]).to include("text-end")
    end

    it "takes a layout per mode" do
      expect(detail(layout: {regular: :grid, embedded: :compact}) { |d| d.attrs :name }
        .at_css(".row.g-3")).to be_present
      expect(detail(embedded, layout: {regular: :grid, embedded: :compact}) { |d| d.attrs :name }
        .at_css("dl.row.small")).to be_present
    end

    it "lets a single group choose its own layout" do
      doc = detail do |d|
        d.attrs :name
        d.attrs :iban, layout: :compact
      end
      expect(doc.at_css("dl.fin-detail-list dd").text).to eq("Testkreditor")
      expect(doc.at_css("dl.row.small dd").text).to eq("XX11 TEST 0000")
    end

    it "rejects a layout that is none of the three" do
      expect { detail(layout: :table) { |d| d.attrs :name } }
        .to raise_error(ArgumentError, /layout must be one of/)
    end
  end

  describe "the blank modes" do
    it "leaves no row behind by default" do
      doc = detail { |d| d.attrs :name, :bic }
      expect(doc.css("dt").map(&:text)).to eq(["Name"])
      expect(doc.to_html).not_to include("—")
    end

    it "writes the muted em dash for a dash field" do
      doc = detail { |d| d.attrs(:bic, bic: {blank: :dash}) }
      expect(doc.css("dt").map(&:text)).to eq(["BIC"])
      expect(doc.at_css("dd span.text-muted").text).to eq("—")
    end

    it "says 'nicht gesetzt' for an unset field, in every layout" do
      doc = detail { |d| d.attrs(:bic, bic: {blank: :unset}) }
      expect(doc.css("dt").map(&:text)).to eq(["BIC"])
      expect(doc.at_css("dd span.text-muted.small").text).to eq("nicht gesetzt")

      compact = detail(embedded) { |d| d.attrs(:bic, bic: {blank: :unset}) }
      expect(compact.at_css("dd span.text-muted.small").text).to eq("nicht gesetzt")

      grid = detail(layout: :grid) { |d| d.attrs(:bic, bic: {blank: :unset}) }
      expect(grid.at_css(".row.g-3 .text-break span.text-muted.small").text)
        .to eq("nicht gesetzt")
    end

    it "keeps the label alone for an empty field" do
      doc = detail { |d| d.attrs(:bic, bic: {blank: :empty}) }
      expect(doc.css("dt").map(&:text)).to eq(["BIC"])
      expect(doc.at_css("dd span.text-muted")).to be_nil
    end

    it "takes the group's blank mode" do
      doc = detail { |d| d.attrs :bic, :moss_vat_id, blank: :dash }
      expect(doc.css("dd span.text-muted").map(&:text)).to eq(%w[— —])
    end

    it "takes the partial's blank mode" do
      doc = detail(blank: :dash) { |d| d.attrs :bic }
      expect(doc.at_css("dd span.text-muted").text).to eq("—")
    end

    # First hit wins: formatter, then field, then group, then partial.
    it "lets the formatter overrule the field's blank mode" do
      stub_helper(:fin_format_wsjrdp_personal_account_bic) { |_obj| {blank: :hide} }
      doc = detail(blank: :dash) { |d| d.attrs(:bic, bic: {blank: :empty}) }
      expect(doc.css("dt")).to be_empty
    end

    it "renders nothing at all for a group whose fields are all blank" do
      doc = detail { |d| d.attrs :bic, :moss_vat_id }
      expect(doc.at_css("dl")).to be_nil
      expect(doc.at_css(".bk-item-detail").children.reject { |n| n.text.strip.empty? })
        .to be_empty
    end

    it "drops a field the formatter hides, whatever its value" do
      stub_helper(:fin_format_wsjrdp_personal_account_name) { |_obj| {hide: true} }
      doc = detail { |d| d.attrs :name, :iban }
      expect(doc.css("dt").map(&:text)).to eq(["IBAN"])
    end
  end

  describe "label, help and tooltip" do
    it "labels a field with the model's attribute name" do
      expect(detail { |d| d.attrs :name }.at_css("dt").text).to eq("Name")
    end

    it "takes the field's own label" do
      doc = detail { |d| d.attrs(:iban, iban: {label: "IBAN (Moss)"}) }
      expect(doc.at_css("dt").text).to eq("IBAN (Moss)")
    end

    it "lets the formatter overrule the field's label" do
      stub_helper(:fin_format_wsjrdp_personal_account_iban) do |obj|
        {value: obj.iban, label: "Bankverbindung"}
      end
      doc = detail { |d| d.attrs(:iban, iban: {label: "IBAN (Moss)"}) }
      expect(doc.at_css("dt").text).to eq("Bankverbindung")
    end

    it "puts the help under the value, muted, in every layout" do
      doc = detail { |d| d.attrs(:iban, iban: {help: "Wie in Moss hinterlegt"}) }
      expect(doc.at_css("dd span.form-text").text).to eq("Wie in Moss hinterlegt")
      compact = detail(embedded) { |d| d.attrs(:iban, iban: {help: "Wie in Moss hinterlegt"}) }
      expect(compact.at_css("dd span.form-text").text).to eq("Wie in Moss hinterlegt")
    end

    it "explains the label with a tooltip" do
      doc = detail { |d| d.attrs(:iban, iban: {tooltip: "Konto des Kreditors"}) }
      expect(doc.at_css("dt")["title"]).to eq("Konto des Kreditors")
      compact = detail(embedded) { |d| d.attrs(:iban, iban: {tooltip: "Konto des Kreditors"}) }
      expect(compact.at_css("dt")["title"]).to eq("Konto des Kreditors")
    end

    it "titles a group" do
      doc = detail { |d| d.section(title: "Bankverbindung") { |s| s.attrs :iban } }
      expect(doc.at_css(".booking-detail-label").text).to eq("Bankverbindung")
    end
  end

  describe "the header" do
    def with_header(ctx)
      detail(ctx) do |d|
        d.header back: "/fin/bookkeeping/personal_accounts", back_label: "Zurück zu Kreditoren",
          label: "Kreditor 700000", title: "Testkreditor"
        d.attrs :name
      end
    end

    it "renders back link, label and title on the record's own page" do
      doc = with_header(regular)
      expect(doc.at_css("a")["href"]).to eq("/fin/bookkeeping/personal_accounts")
      expect(doc.at_css("a").text).to include("Zurück zu Kreditoren")
      expect(doc.at_css("h1").text).to include("Kreditor 700000", "Testkreditor")
    end

    it "renders no header in an embedded pane" do
      doc = with_header(embedded)
      expect(doc.at_css("h1")).to be_nil
      expect(doc.at_css("a")).to be_nil
    end
  end

  # A d.raw_data area renders where it was declared and holds the d.raw_entries
  # blocks declared inside it, each under its own title.
  describe "the raw area" do
    before do
      account.other_datev_columns = {"Kurzbezeichnung" => "TESTKRED", "Zahlungsträger" => "1",
                                     "Leer" => ""}
      account.other_moss_columns = {"VAT Rate" => "19"}
    end

    # One entries block, alone in the area.
    def raw_detail(ctx = regular, open: nil, area_title: nil, **options)
      detail(ctx) do |d|
        d.raw_data(title: area_title, open: open) do |r|
          r.raw_entries :other_datev_columns, title: "DATEV Rohdaten", **options
        end
      end
    end

    # One area with both entries blocks, declared between two groups of fields.
    def two_blocks(ctx = regular, open: nil)
      detail(ctx) do |d|
        d.attrs :name
        d.raw_data(open: open) do |r|
          r.raw_entries :other_datev_columns, title: "DATEV Rohdaten"
          r.raw_entries :other_moss_columns, title: "Moss Rohdaten"
        end
        d.attrs :iban
      end
    end

    # The titles of the entries blocks; the area's own summary is no div.
    def block_titles(doc) = doc.css("details.fin-detail-raw div.booking-detail-label").map(&:text)

    it "renders one collapsible area for the blocks declared inside it" do
      doc = two_blocks
      expect(doc.css("details").size).to eq(1)
      expect(doc.at_css("details")["class"]).to eq("fin-detail-raw")
      expect(doc.at_css("details > summary").text.squish).to eq("Rohdaten")
    end

    it "heads the area with its own title when it has one" do
      expect(raw_detail(area_title: "DATEV").at_css("details > summary").text.squish)
        .to eq("DATEV")
    end

    it "titles the entries blocks in declaration order" do
      expect(block_titles(two_blocks)).to eq(["DATEV Rohdaten", "Moss Rohdaten"])
    end

    # Header and field groups come first (they are what an editable partial
    # wraps in its form); the raw areas follow them, whatever the declaration
    # order, and the field groups keep their order among themselves.
    it "stands after the groups of fields, whichever came first in the declaration" do
      children = two_blocks.at_css(".bk-item-detail").element_children
      expect(children.map { |node| node.at_css("details.fin-detail-raw") ? :raw : node.name })
        .to eq(["dl", "dl", :raw])
      expect(children.first.at_css("dt").text).to eq("Name")
      expect(children[1].at_css("dt").text).to eq("IBAN")
    end

    it "renders every declared area after the fields, in declaration order" do
      doc = detail do |d|
        d.raw_data(title: "DATEV") { |r| r.raw_entries :other_datev_columns, title: "Spalten" }
        d.attrs :name
        d.raw_data(title: "Moss") { |r| r.raw_entries :other_moss_columns, title: "Spalten" }
      end
      children = doc.at_css(".bk-item-detail").element_children
      expect(children.map { |node| node.at_css("details.fin-detail-raw") ? :raw : node.name })
        .to eq(["dl", :raw, :raw])
      expect(doc.css("details > summary").map { |node| node.text.squish }).to eq(%w[DATEV Moss])
    end

    it "lists the entries of a block as key/value lines, keys verbatim" do
      lines = raw_detail.css("details .font-monospace .text-break").map { |line| line.text.squish }
      expect(lines).to eq(["Kurzbezeichnung: TESTKRED", "Zahlungsträger: 1"])
    end

    it "stands open on the record's own page and collapsed in an embedded pane" do
      expect(raw_detail.at_css("details").attributes).to have_key("open")
      expect(raw_detail(embedded).at_css("details").attributes).not_to have_key("open")
    end

    it "takes the open: override of the area, in both directions" do
      expect(raw_detail(open: false).at_css("details").attributes).not_to have_key("open")
      expect(two_blocks(embedded, open: true).at_css("details").attributes).to have_key("open")
    end

    it "leaves the exclude: keys out and keeps their neighbours" do
      lines = raw_detail(exclude: "Zahlungsträger").css(".text-break").map { |l| l.text.squish }
      expect(lines).to eq(["Kurzbezeichnung: TESTKRED"])
    end

    it "never asks the raw helper about an excluded key" do
      asked = []
      stub_helper(:fin_raw_format_other_wsjrdp_personal_account) do |_obj, key, _context|
        asked << key
        nil
      end
      raw_detail(exclude: %w[Zahlungsträger Leer])
      expect(asked).to eq(["Kurzbezeichnung"])
    end

    it "appends the also: columns, keyed by their column name" do
      lines = raw_detail(also: [:datev_short_name]).css(".text-break").map { |l| l.text.squish }
      expect(lines.last).to eq("datev_short_name: TESTKRED")
    end

    it "shows a blank entry when the block asks for the dash" do
      lines = raw_detail(blank: :dash).css(".text-break").map { |line| line.text.squish }
      expect(lines.last).to eq("Leer: —")
    end

    it "shows a blank entry as 'nicht gesetzt' when the block asks for unset" do
      lines = raw_detail(blank: :unset).css(".text-break").map { |line| line.text.squish }
      expect(lines.last).to eq("Leer: nicht gesetzt")
    end

    it "leaves no title behind for an entries block whose entries are all blank" do
      account.other_moss_columns = {"VAT Rate" => ""}
      doc = two_blocks
      expect(block_titles(doc)).to eq(["DATEV Rohdaten"])
      expect(doc.to_html).not_to include("Moss Rohdaten")
    end

    it "renders no area at all when no block shows an entry" do
      account.other_datev_columns = {}
      account.other_moss_columns = {}
      expect(two_blocks.at_css("details")).to be_nil
    end

    it "passes the source to the model's raw helper" do
      stub_helper(:fin_raw_format_other_wsjrdp_personal_account) do |_obj, key, context|
        "#{context.raw_source}/#{key}"
      end
      lines = raw_detail.css(".text-break").map { |line| line.text.squish }
      expect(lines.first).to eq("Kurzbezeichnung: other_datev_columns/Kurzbezeichnung")
    end
  end

  # The label typography of the :list layout: one class on the dl, one style
  # block for the whole response.
  describe "the kit's style block" do
    it "marks the list layout's dl with the kit's class" do
      dl = detail { |d| d.attrs :name }.at_css("dl")
      expect(dl["class"].split).to include("fin-detail-list")
    end

    it "emits the style block once, however many details a response renders" do
      doc = detail { |d| d.attrs :name }
      expect(doc.css("style").size).to eq(1)
      expect(doc.at_css("style").text).to include(".fin-detail-list dt")
      expect(doc.at_css("style").text).to include("font-weight: 400")

      expect(detail(embedded) { |d| d.attrs :name }.css("style")).to be_empty
    end
  end

  describe "a custom section" do
    it "passes the captured HTML through" do
      doc = detail do |d|
        d.custom(title: "Verknüpfungen") { helper.content_tag(:span, "Widget", class: "custom") }
      end
      expect(doc.at_css("span.custom").text).to eq("Widget")
      expect(doc.at_css(".booking-detail-label").text).to eq("Verknüpfungen")
    end
  end
end
