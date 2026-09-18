# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Deliberately standalone (no rails spec_helper): the builder is pure Ruby --
# it collects what a detail partial declares, the helper renders it afterwards.
module Fin; end
require_relative "../../../app/domain/fin/detail_value"
require_relative "../../../app/domain/fin/detail_builder"

# The declaration half of `= fin_detail(record, ctx) do |d| ... end`.
describe Fin::DetailBuilder do
  subject(:builder) { described_class.new }

  # The kinds of the declared sections, in declaration order.
  def kinds = builder.to_sections.map(&:kind)

  # The attributes of the n-th section, in declaration order.
  def attrs_of(index) = builder.to_sections[index].items.map(&:attr)

  it "declares nothing for a fresh builder" do
    expect(builder.to_sections).to eq([])
  end

  describe "#header" do
    it "keeps the technical label, the record's title, links and slots" do
      builder.header(back: "/fin/bookkeeping/personal_accounts", back_label: "Zurück",
        label: "Kreditor 700000", title: "Kurzname", toolbar: "<button>")
      section = builder.to_sections.first
      expect(section.kind).to eq(:header)
      expect(section.title).to eq("Kurzname")
      expect(section.options).to eq(back: "/fin/bookkeeping/personal_accounts",
        back_label: "Zurück", label: "Kreditor 700000", toolbar: "<button>")
    end

    it "leaves title and toolbar empty when the page has none" do
      builder.header(back: "/fin", back_label: "Zurück", label: "Kreditor 700000")
      section = builder.to_sections.first
      expect(section.title).to be_nil
      expect(section.options).to include(toolbar: nil)
    end
  end

  describe "#attrs" do
    it "declares one group of fields in the given order" do
      builder.attrs :name, :short_name, :iban
      expect(kinds).to eq([:fields])
      expect(attrs_of(0)).to eq(%i[name short_name iban])
      expect(builder.to_sections.first.items.map(&:options)).to all(eq({}))
    end

    it "splits the group's own keys off the per-field ones" do
      builder.attrs :iban, :bic, layout: :grid, title: "Bank", blank: :dash,
        bic: {blank: :empty, span: 2}
      section = builder.to_sections.first
      expect(section.layout).to eq(:grid)
      expect(section.title).to eq("Bank")
      expect(section.blank).to eq(:dash)
      expect(attrs_of(0)).to eq(%i[iban bic])
      expect(section.items.first.options).to eq({})
      expect(section.items.last.options).to eq(blank: :empty, span: 2)
    end

    it "declares a group per call" do
      builder.attrs :name
      builder.attrs :iban, :bic
      expect(kinds).to eq(%i[fields fields])
      expect(attrs_of(1)).to eq(%i[iban bic])
    end

    it "takes String attribute names as symbols" do
      builder.attrs "name", "iban"
      expect(attrs_of(0)).to eq(%i[name iban])
    end

    # A per-field key naming nothing in the list would silently apply to nothing.
    it "rejects per-field options for an attribute the group does not list" do
      expect { builder.attrs(:iban, bci: {blank: :dash}) }
        .to raise_error(ArgumentError, /bci is not among the attributes/)
    end

    it "rejects a field option it does not know" do
      expect { builder.attrs(:iban, iban: {lable: "IBAN"}) }
        .to raise_error(ArgumentError, /unknown field option\(s\) lable/)
    end

    # `extra` names a helper that renders one more control beside the field's
    # input; the builder only carries it through to the row.
    it "carries the extra: control of an editable field" do
      builder.attrs(:iban, iban: {editable: true, input: :select, extra: :fin_new_thing_field})
      expect(builder.to_sections.first.items.first.options)
        .to eq(editable: true, input: :select, extra: :fin_new_thing_field)
    end

    it "rejects a layout that is none of the three" do
      expect { builder.attrs(:iban, layout: :table) }
        .to raise_error(ArgumentError, /layout must be one of list, compact, grid/)
    end

    it "rejects a blank mode that is none of them" do
      expect { builder.attrs(:iban, blank: :dashed) }
        .to raise_error(ArgumentError, /blank must be one of hide, dash, empty, unset/)
      expect { builder.attrs(:iban, iban: {blank: :dashed}) }
        .to raise_error(ArgumentError, /blank must be one of hide, dash, empty, unset/)
    end
  end

  describe "#attr" do
    it "declares a group of its own" do
      builder.attr :comment, label: "Kommentar", blank: :empty
      expect(kinds).to eq([:fields])
      expect(attrs_of(0)).to eq([:comment])
      expect(builder.to_sections.first.items.first.options)
        .to eq(label: "Kommentar", blank: :empty)
    end

    it "rejects a field option it does not know" do
      expect { builder.attr(:comment, titel: "x") }
        .to raise_error(ArgumentError, /unknown field option\(s\) titel/)
    end
  end

  describe "#section" do
    it "collects the fields declared inside it" do
      builder.section(title: "Bankverbindung", layout: :grid, blank: :dash) do |d|
        d.attrs :iban, :bic
        d.attr :moss_default_payment_method
      end
      expect(kinds).to eq([:fields])
      section = builder.to_sections.first
      expect(section.title).to eq("Bankverbindung")
      expect(section.layout).to eq(:grid)
      expect(section.blank).to eq(:dash)
      expect(attrs_of(0)).to eq(%i[iban bic moss_default_payment_method])
    end

    it "closes again, so the next call is a group of its own" do
      builder.section(title: "Bank") { |d| d.attrs :iban }
      builder.attrs :name
      expect(kinds).to eq(%i[fields fields])
      expect(attrs_of(0)).to eq([:iban])
      expect(attrs_of(1)).to eq([:name])
    end

    it "closes again even when the block raises" do
      expect { builder.section(title: "Bank") { raise "boom" } }.to raise_error("boom")
      builder.attrs :name
      expect(kinds).to eq(%i[fields fields])
      expect(attrs_of(1)).to eq([:name])
    end

    it "keeps the group's keys with the section, not with the fields inside it" do
      expect { builder.section(title: "Bank") { |d| d.attrs(:iban, layout: :grid) } }
        .to raise_error(ArgumentError, /belong to d.section here/)
    end

    it "cannot be nested" do
      expect { builder.section { |d| d.section { nil } } }
        .to raise_error(ArgumentError, /cannot be nested/)
    end

    it "needs a block" do
      expect { builder.section(title: "Bank") }.to raise_error(ArgumentError, /needs a block/)
    end

    it "rejects a layout that is none of the three" do
      expect { builder.section(layout: :table) { nil } }
        .to raise_error(ArgumentError, /layout must be one of/)
    end
  end

  # One area per #raw_data call, holding the #raw_entries blocks declared
  # inside it; the area carries the title and the open state, a block the
  # jsonb column it lists.
  describe "#raw_data" do
    # The entries blocks of the n-th section, in declaration order.
    def entries_of(index) = builder.to_sections[index].items

    it "declares one area holding the blocks inside it" do
      builder.raw_data do |d|
        d.raw_entries :other_datev_columns, title: "DATEV Rohdaten"
        d.raw_entries :other_moss_columns, title: "Moss Rohdaten"
      end
      section = builder.to_sections.first
      expect(kinds).to eq([:raw_data])
      expect(section.title).to be_nil
      expect(section.options).to eq(open: nil)
      expect(entries_of(0).map(&:title)).to eq(["DATEV Rohdaten", "Moss Rohdaten"])
      expect(entries_of(0).map(&:source)).to eq(%i[other_datev_columns other_moss_columns])
    end

    it "keeps the area's own title and open state" do
      builder.raw_data(title: "DATEV Rohdaten", open: false) do |d|
        d.raw_entries :other_datev_columns, title: "Spalten"
      end
      section = builder.to_sections.first
      expect(section.title).to eq("DATEV Rohdaten")
      expect(section.options).to eq(open: false)
    end

    it "declares an area per call, each with its own blocks" do
      builder.raw_data { |d| d.raw_entries :other_datev_columns, title: "DATEV Rohdaten" }
      builder.attrs :name
      builder.raw_data(open: true) { |d| d.raw_entries :other_moss_columns, title: "Moss Rohdaten" }
      expect(kinds).to eq(%i[raw_data fields raw_data])
      expect(entries_of(0).map(&:title)).to eq(["DATEV Rohdaten"])
      expect(entries_of(2).map(&:title)).to eq(["Moss Rohdaten"])
      expect(builder.to_sections.last.options).to eq(open: true)
    end

    it "closes again, so the next call is a section of its own" do
      builder.raw_data { |d| d.raw_entries :other_datev_columns, title: "DATEV Rohdaten" }
      builder.attrs :name
      expect(kinds).to eq(%i[raw_data fields])
    end

    it "closes again even when the block raises" do
      expect { builder.raw_data { raise "boom" } }.to raise_error("boom")
      builder.attrs :name
      expect(kinds).to eq(%i[raw_data fields])
    end

    it "needs a block" do
      expect { builder.raw_data(title: "Rohdaten") }
        .to raise_error(ArgumentError, /d.raw_data needs a block/)
    end

    it "cannot be nested" do
      expect { builder.raw_data { |d| d.raw_data { nil } } }
        .to raise_error(ArgumentError, /d.raw_data cannot be nested/)
    end

    it "cannot be opened inside a d.section" do
      expect { builder.section(title: "Bank") { |d| d.raw_data { nil } } }
        .to raise_error(ArgumentError, /d.raw_data cannot be opened inside d.section/)
    end
  end

  describe "#raw_entries" do
    def entries = builder.to_sections.first.items

    it "names the jsonb column and its title" do
      builder.raw_data { |d| d.raw_entries :other_datev_columns, title: "DATEV Rohdaten" }
      expect(entries.first)
        .to eq(Fin::DetailBuilder::RawEntries.new(source: :other_datev_columns,
          title: "DATEV Rohdaten", also: [], exclude: [], blank: :hide))
    end

    it "appends the also: columns, keyed by their column name" do
      builder.raw_data do |d|
        d.raw_entries :other_datev_columns, title: "DATEV Rohdaten",
          also: [:datev_short_name, "datev_nummer_fremdsystem"], blank: :dash
      end
      expect(entries.first.also).to eq(%i[datev_short_name datev_nummer_fremdsystem])
      expect(entries.first.blank).to eq(:dash)
    end

    it "takes a single also: column without a list" do
      builder.raw_data do |d|
        d.raw_entries :other_moss_columns, title: "Moss Rohdaten", also: :moss_uuid
      end
      expect(entries.first.also).to eq([:moss_uuid])
    end

    it "keeps the exclude: keys as strings, single ones without a list" do
      builder.raw_data do |d|
        d.raw_entries :other_datev_columns, title: "DATEV Rohdaten",
          exclude: [:Kurzbezeichnung, "Zahlungsträger"]
        d.raw_entries :other_moss_columns, title: "Moss Rohdaten", exclude: :Sprache
      end
      expect(entries.first.exclude).to eq(%w[Kurzbezeichnung Zahlungsträger])
      expect(entries.last.exclude).to eq(%w[Sprache])
    end

    it "knows no open state of its own -- the area's open: decides" do
      expect {
        builder.raw_data do |d|
          d.raw_entries(:other_moss_columns, title: "Moss Rohdaten", open: true)
        end
      }.to raise_error(ArgumentError, /open/)
    end

    it "rejects a blank mode that is none of them" do
      expect {
        builder.raw_data { |d| d.raw_entries(:other_moss_columns, title: "R", blank: :drop) }
      }.to raise_error(ArgumentError, /blank must be one of/)
    end

    it "belongs inside a d.raw_data area" do
      expect { builder.raw_entries(:other_datev_columns, title: "DATEV Rohdaten") }
        .to raise_error(ArgumentError, "d.raw_entries belongs inside d.raw_data")
      expect {
        builder.section(title: "Bank") { |d| d.raw_entries(:other_datev_columns, title: "R") }
      }.to raise_error(ArgumentError, "d.raw_entries belongs inside d.raw_data")
    end
  end

  describe "#custom" do
    it "stores what the block returns when nobody captures" do
      builder.custom(title: "Verknüpfungen") { "<div>Widget</div>" }
      section = builder.to_sections.first
      expect(section.kind).to eq(:custom)
      expect(section.title).to eq("Verknüpfungen")
      expect(section.html).to eq("<div>Widget</div>")
      expect(section.key).to be_nil
    end

    it "keeps the key a only: list addresses it by" do
      builder.custom(key: :links, title: "Verknüpfungen") { "<div></div>" }
      expect(builder.to_sections.first.key).to eq(:links)
    end

    it "stores what the view's capture makes of the block" do
      capturing = described_class.new(capture: ->(&block) { "[#{block.call}]" })
      capturing.custom { "Widget" }
      expect(capturing.to_sections.first.html).to eq("[Widget]")
    end

    it "needs a block" do
      expect { builder.custom(title: "Verknüpfungen") }
        .to raise_error(ArgumentError, /needs a block/)
    end
  end

  describe "#bookings" do
    it "carries the rows and the link of the embedded bookings list" do
      rows = Object.new
      builder.bookings rows, show_all_path: "/fin/bookkeeping/bookings?f=x",
        all_label: "In Buchungen-Ansicht öffnen"
      section = builder.to_sections.first
      expect(section.kind).to eq(:bookings)
      expect(section.options[:rows]).to equal(rows)
      expect(section.options[:show_all_path]).to eq("/fin/bookkeeping/bookings?f=x")
      expect(section.options[:all_label]).to eq("In Buchungen-Ansicht öffnen")
    end
  end

  describe "#to_sections" do
    it "keeps every kind in declaration order" do
      builder.header(back: "/fin", back_label: "Zurück", label: "Kreditor 700000")
      builder.attrs :name
      builder.section(title: "Bank") { |d| d.attrs :iban }
      builder.raw_data { |d| d.raw_entries :other_datev_columns, title: "DATEV Rohdaten" }
      builder.custom { "<div></div>" }
      builder.bookings [], show_all_path: "/fin", all_label: "Alle"
      expect(kinds).to eq(%i[header fields fields raw_data custom bookings])
      expect(kinds - Fin::DetailBuilder::KINDS).to be_empty
    end

    it "freezes the field lists -- the declaration phase is over" do
      builder.attrs :name
      expect(builder.to_sections.first.items).to be_frozen
    end
  end

  # A host that shows the same partial with FEWER fields hands the builder its
  # field list instead of writing a partial of its own: the fields it names, the
  # keyed sections it names, and the header, which is the page's own frame.
  describe "only:" do
    subject(:builder) { described_class.new(only: only) }

    let(:only) { %i[name iban links] }

    # The partial every example below declares, in full.
    def declare(target = builder)
      target.header(back: "/fin", back_label: "Zurück", label: "Kreditor 700000")
      target.attrs :name, :short_name, :iban
      target.attrs :bic
      target.raw_data(key: :raw) { |d| d.raw_entries :other_datev_columns, title: "DATEV Rohdaten" }
      target.custom(key: :links, title: "Verknüpfungen") { "<div></div>" }
      target.custom(key: :moss, title: "Moss") { "<div></div>" }
    end

    it "keeps the listed fields and drops the rest" do
      declare
      expect(kinds).to eq(%i[header fields custom])
      expect(attrs_of(1)).to eq(%i[name iban])
    end

    it "drops a field group the list leaves empty" do
      declare
      expect(builder.to_sections.map(&:title)).not_to include("bic")
      expect(builder.to_sections.flat_map { |s| s.items.to_a.map(&:attr) }).to eq(%i[name iban])
    end

    it "keeps a keyed section the list names and drops the others" do
      declare
      expect(builder.to_sections.last.key).to eq(:links)
      expect(builder.to_sections.map(&:key)).not_to include(:raw, :moss)
    end

    it "keeps the header, which is the page's own frame" do
      declare
      expect(kinds.first).to eq(:header)
      expect(builder.to_sections.first.options[:label]).to eq("Kreditor 700000")
    end

    it "takes the list as Strings too" do
      strings = described_class.new(only: %w[name links])
      declare(strings)
      expect(strings.to_sections.map(&:kind)).to eq(%i[header fields custom])
      expect(strings.to_sections[1].items.map(&:attr)).to eq([:name])
    end

    # A keyed kind without a key: could never appear in the list, so it would
    # vanish silently -- which is a declaration mistake, not a hidden section.
    it "raises for a keyed section that has no key:, naming it" do
      builder.custom(title: "Verknüpfungen") { "<div></div>" }
      expect { builder.to_sections }
        .to raise_error(ArgumentError, /d.custom \(Verknüpfungen\) needs a key:/)
    end

    it "names the kind alone when the section has no title either" do
      builder.bookings [], show_all_path: "/fin", all_label: "Alle"
      expect { builder.to_sections }.to raise_error(ArgumentError, /d.bookings needs a key:/)
      builder2 = described_class.new(only: only)
      builder2.raw_data { |d| d.raw_entries :other_datev_columns, title: "R" }
      expect { builder2.to_sections }.to raise_error(ArgumentError, /d.raw_data needs a key:/)
    end

    # Without a list nothing is dropped and a missing key: is nobody's business.
    it "changes nothing when it is not given" do
      plain = described_class.new
      declare(plain)
      plain.custom(title: "Ohne Key") { "<div></div>" }
      expect(plain.to_sections.map(&:kind)).to eq(%i[header fields fields raw_data custom custom custom])
    end
  end
end
