# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Deliberately standalone (no rails spec_helper): the chips are pure value logic
# over a catalog Hash and the applied filter tree -- the spec needs neither the
# app nor a database. Runs from the wagon root:
#
#   bundle exec rspec spec/domain/wsjrdp/filter_chips_spec.rb
require "active_support"
require "active_support/core_ext/object/blank"
require "active_support/number_helper"

module Wsjrdp; end
require_relative "../../../app/domain/wsjrdp/filtering/slot_equality"
require_relative "../../../app/domain/wsjrdp/table_state"
require_relative "../../../app/domain/wsjrdp/filter_chips"

# A hand-written stand-in for Wsjrdp::Filtering::BoundSchema#catalog, in exactly
# its shape (symbol Hash keys, Symbol attribute / operator keys, Symbol arity,
# inline options as [value, label] pairs) -- reduced to the five attributes these
# examples need: a reference with options, a decimal, its magnitude twin (the
# two are one sign pair), a date and a text one.
CHIP_CATALOG = {
  attributes: [
    {key: :cost_center, label: "Kostenstelle", group: "Felder", type: :reference,
     control: "multiselect",
     operators: [
       {key: :in, label: "ist", arity: :many, label_many: "ist eines von",
        many_hint: "Mehrfachauswahl: es genügt, wenn EINER der Werte zutrifft (ODER)."},
       {key: :not_in, label: "ist nicht", arity: :many, label_many: "ist keines von"},
       {key: :blank, label: "ist leer", arity: :none}
     ],
     options: {mode: "inline",
               values: [["3150", "3150 Kostenstelle A"], ["3160", "3160 Kostenstelle B"]]}},
    {key: :amount, label: "Betrag", group: "Felder", type: :decimal,
     control: "number_range", variant_group: "Betrag", sign: :signed,
     operators: [
       {key: :gte, label: "≥", arity: :one},
       {key: :between, label: "im Bereich", arity: :two},
       {key: :nonzero, label: "≠ 0", arity: :none}
     ],
     options: nil},
    {key: :amount_abs, label: "|Betrag|", group: "Felder", type: :decimal,
     control: "number_range", variant_group: "Betrag", sign: :absolute,
     operators: [
       {key: :gte, label: "≥", arity: :one},
       {key: :between, label: "im Bereich", arity: :two},
       {key: :nonzero, label: "≠ 0", arity: :none}
     ],
     options: nil},
    {key: :booking_date, label: "Buchungsdatum", group: "Felder", type: :date,
     control: "date_range",
     operators: [
       {key: :gte, label: "ab", arity: :one},
       {key: :between, label: "im Bereich", arity: :two},
       {key: :in_month, label: "im Monat", arity: :one}
     ],
     options: nil},
    {key: :text, label: "Freitext", group: "Felder", type: :text, control: "text",
     operators: [
       {key: :contains, label: "enthält", arity: :one,
        case_group: :contains, case_sensitive: false},
       {key: :contains_cs, label: "enthält (Groß/Klein)", arity: :one,
        case_group: :contains, case_sensitive: true},
       {key: :glob, label: "Glob", arity: :one, case_group: :glob, case_sensitive: false,
        hint: "* steht für beliebig viele Zeichen, ? für genau eines; " \
              "das Muster muss den ganzen Text treffen."}
     ],
     options: nil}
  ]
}.freeze

describe Wsjrdp::FilterChips do
  # The real preset value object -- the class only ever asks it for `slots` and
  # `active?`, so anything answering those two would do just as well.
  def preset(slots, active:)
    Wsjrdp::TableState::FilterPreset.new(key: "preset", label: "Preset", slots: slots,
      active: active, toggle_wire: "")
  end

  # One member of a quick-select GROUP: several buttons sharing one
  # `attribute in (values)` slot, one value each. Of such a preset the class asks
  # `group?`, `attribute` and `group_values` -- and `slots`, which is nil.
  def group_member(value, values, active: false)
    Wsjrdp::TableState::FilterPreset.new(key: value, label: value, slots: nil,
      active: active, toggle_wire: "", group: "kostenstelle", attribute: "cost_center",
      value: value, group_values: values)
  end

  def build(user_slots, presets: [])
    described_class.new(catalog: CHIP_CATALOG, user_slots: user_slots, presets: presets)
  end

  def texts(user_slots, presets: [])
    build(user_slots, presets: presets).chips.map(&:text)
  end

  # One condition, worded on its own.
  def text(condition)
    texts([[condition]]).first
  end

  describe "one chip per slot" do
    it "words every slot, in slot order" do
      expect(texts([[["cost_center", "in", "3150"]],
        [["amount", "gte", 100]],
        [["booking_date", "gte", "2026-05-01"]]]))
        .to eq ["Kostenstelle ist 3150 Kostenstelle A", "Betrag ≥ 100",
          "Buchungsdatum ab 01.05.2026"]
    end

    it "joins the conditions of ONE slot with ' oder '" do
      chip = build([[["cost_center", "in", "3150"], ["amount", "nonzero"]]]).chips.first

      expect(chip.text).to eq "Kostenstelle ist 3150 Kostenstelle A oder Betrag ≠ 0"
      expect(chip.conditions).to eq ["Kostenstelle ist 3150 Kostenstelle A", "Betrag ≠ 0"]
    end

    it "carries the raw slot, so a chip can act on itself" do
      slot = [["amount", "nonzero"]]

      expect(build([slot]).chips.first.slot).to eq slot
    end

    it "drops a slot without conditions" do
      expect(texts([[], [["amount", "nonzero"]]])).to eq ["Betrag ≠ 0"]
    end
  end

  describe "wording (mirrors the builder's condFullText)" do
    it "uses the plain label for one operand and label_many for several" do
      expect(text(["cost_center", "in", "3150"])).to eq "Kostenstelle ist 3150 Kostenstelle A"
      expect(text(["cost_center", "in", "3150", "3160"]))
        .to eq "Kostenstelle ist eines von 3150 Kostenstelle A, 3160 Kostenstelle B"
      expect(text(["cost_center", "not_in", "3150", "3160"]))
        .to eq "Kostenstelle ist keines von 3150 Kostenstelle A, 3160 Kostenstelle B"
    end

    it "falls back to the raw value for an option the catalog does not list" do
      expect(text(["cost_center", "in", "9999"])).to eq "Kostenstelle ist 9999"
    end

    it "joins the two operands of a range with an en dash" do
      expect(text(["amount", "between", 100, 2500])).to eq "Betrag im Bereich 100 – 2.500"
      expect(text(["booking_date", "between", "2026-05-01", "2026-05-31"]))
        .to eq "Buchungsdatum im Bereich 01.05.2026 – 31.05.2026"
    end

    it "shows dates German, whole days and whole months alike" do
      expect(text(["booking_date", "gte", "2026-05-01"])).to eq "Buchungsdatum ab 01.05.2026"
      expect(text(["booking_date", "in_month", "2026-05"])).to eq "Buchungsdatum im Monat 05.2026"
    end

    it "delimits numeric operands German-style, and leaves strings alone" do
      expect(text(["amount", "gte", 1234567.5])).to eq "Betrag ≥ 1.234.567,5"
      expect(text(["amount", "gte", "100"])).to eq "Betrag ≥ 100"
    end

    it "leaves an operand-less operator at attribute + operator" do
      expect(text(["amount", "nonzero"])).to eq "Betrag ≠ 0"
      expect(text(["cost_center", "blank"])).to eq "Kostenstelle ist leer"
    end

    it "words a text condition, case sensitivity included (it is in the label)" do
      expect(text(["text", "contains", "Muster"])).to eq "Freitext enthält Muster"
      expect(text(["text", "contains_cs", "Muster"]))
        .to eq "Freitext enthält (Groß/Klein) Muster"
    end

    # A glob keeps its wildcards verbatim: the pattern IS the operand, and the
    # operator's editor hint stays in the editor.
    it "words a glob condition with its pattern unchanged" do
      expect(text(["text", "glob", "AB*"])).to eq "Freitext Glob AB*"
      expect(text(["text", "glob", "AB-?? *"])).to eq "Freitext Glob AB-?? *"
    end

    it "falls back to the KEY of an attribute the catalog does not know" do
      expect(text(["unbekannt", "in", "5"])).to eq "unbekannt in 5"
      expect(text(["unbekannt", "blank"])).to eq "unbekannt blank"
    end

    it "falls back to the KEY of an operator the attribute does not know" do
      expect(text(["amount", "frobnicate", 5])).to eq "Betrag frobnicate 5"
    end
  end

  describe "presets" do
    let(:preset_slot) { [["cost_center", "in", "3150"]] }
    let(:other_slot) { [["amount", "nonzero"]] }

    it "leaves out a slot equal to an ACTIVE preset's slot" do
      expect(texts([preset_slot, other_slot], presets: [preset([preset_slot], active: true)]))
        .to eq ["Betrag ≠ 0"]
    end

    it "keeps the same slot next to an INACTIVE preset" do
      expect(texts([preset_slot, other_slot], presets: [preset([preset_slot], active: false)]))
        .to eq ["Kostenstelle ist 3150 Kostenstelle A", "Betrag ≠ 0"]
    end

    it "keeps every slot when there are no presets at all" do
      expect(texts([preset_slot, other_slot])).to eq ["Kostenstelle ist 3150 Kostenstelle A",
        "Betrag ≠ 0"]
    end

    it "goes by slot EQUALITY, not by condition order (SlotEquality)" do
      slot = [["amount", "nonzero"], ["cost_center", "in", "3150"]]
      reversed = [[["cost_center", "in", "3150"], ["amount", "nonzero"]]]

      expect(texts([slot], presets: [preset(reversed, active: true)])).to eq []
    end

    it "keeps a slot that OR-widens an active preset's slot" do
      widened = [["cost_center", "in", "3150"], ["amount", "nonzero"]]

      expect(texts([widened], presets: [preset([preset_slot], active: true)]))
        .to eq ["Kostenstelle ist 3150 Kostenstelle A oder Betrag ≠ 0"]
    end

    # `≠ 0` asks nothing about the sign, so the signed twin of a preset on the
    # magnitude is the SAME condition -- the toggle shows it, and a chip would
    # say it a second time. The sign pair comes from the catalog itself.
    it "leaves out the signed twin of an active preset's sign-invariant slot" do
      magnitude = preset([[["amount_abs", "nonzero"]]], active: true)

      expect(texts([[["amount", "nonzero"]]], presets: [magnitude])).to eq []
      expect(texts([[["amount", "nonzero"]], preset_slot], presets: [magnitude]))
        .to eq ["Kostenstelle ist 3150 Kostenstelle A"]
      expect(texts([[["amount", "eq", 0]]],
        presets: [preset([[["amount_abs", "eq", 0]]], active: true)])).to eq []
    end

    # A comparison is member-specific: |Betrag| ≥ 100 and Betrag ≥ 100 are two
    # different questions, so the chip stays.
    it "keeps the signed twin of a comparison" do
      expect(texts([[["amount", "gte", 100]]],
        presets: [preset([[["amount_abs", "gte", 100]]], active: true)]))
        .to eq ["Betrag ≥ 100"]
    end
  end

  # The members of a GROUP share one slot, `attribute in (values)`, and each
  # pressed button says its own value -- so that slot needs no chip as long as
  # every value in it belongs to a member.
  describe "a group" do
    let(:values) { %w[3150 3160] }
    let(:members) { [group_member("3150", values, active: true), group_member("3160", values)] }

    it "leaves out a slot of member values only, whichever buttons are pressed" do
      expect(texts([[["cost_center", "in", "3150"]]], presets: members)).to eq []
      expect(texts([[["cost_center", "in", "3150", "3160"]]], presets: members)).to eq []
      expect(texts([[["cost_center", "in", "3160"]]], presets: members)).to eq []
    end

    it "keeps a slot that carries a value of no member" do
      expect(texts([[["cost_center", "in", "3150", "3170"]]], presets: members))
        .to eq ["Kostenstelle ist eines von 3150 Kostenstelle A, 3170"]
    end

    it "keeps a slot the group does not speak for" do
      expect(texts([[["cost_center", "not_in", "3150"]]], presets: members))
        .to eq ["Kostenstelle ist nicht 3150 Kostenstelle A"]
      expect(texts([[["cost_center", "in", "3150"], ["amount", "nonzero"]]], presets: members))
        .to eq ["Kostenstelle ist 3150 Kostenstelle A oder Betrag ≠ 0"]
      expect(texts([[["amount", "gte", 100]]], presets: members)).to eq ["Betrag ≥ 100"]
    end

    it "goes by the group's attribute, so the same shape on another one keeps its chip" do
      expect(texts([[["text", "in", "3150"]]], presets: members)).to eq ["Freitext in 3150"]
    end

    it "changes nothing while no slot is the group's" do
      expect(texts([[["booking_date", "gte", "2026-05-01"]]], presets: members))
        .to eq ["Buchungsdatum ab 01.05.2026"]
      expect(texts([], presets: members)).to eq []
    end
  end

  describe "emptiness and counting" do
    it "is empty without user slots" do
      chips = build([])

      expect(chips.chips).to eq []
      expect(chips).to be_empty
      expect(chips.any?).to be false
      expect(chips.count).to eq 0
    end

    it "is empty when every slot belongs to an active preset" do
      slot = [["amount", "nonzero"]]

      expect(build([slot], presets: [preset([slot], active: true)])).to be_empty
    end

    it "counts the conditions over ALL chips" do
      chips = build([[["cost_center", "in", "3150"], ["amount", "nonzero"]],
        [["booking_date", "gte", "2026-05-01"]]])

      expect(chips.chips.size).to eq 2
      expect(chips.count).to eq 3
      expect(chips.any?).to be true
    end
  end
end
