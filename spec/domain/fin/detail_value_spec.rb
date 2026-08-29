# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Deliberately standalone (no rails spec_helper): Fin::DetailValue is a pure
# Data object. Output safety comes from active_support alone, which is what an
# html-safe formatter result is.
require "active_support"
require "active_support/core_ext/string/output_safety"
module Fin; end
require_relative "../../../app/domain/fin/detail_value"

# What a finance formatter hands back, normalised: the plain String of a
# one-liner, an html-safe buffer, nil, a Hash of keys or a DetailValue itself.
describe Fin::DetailValue do
  describe ".wrap" do
    it "puts a plain String into the value" do
      value = described_class.wrap("XX11TEST")
      expect(value.value).to eq("XX11TEST")
      expect(value.help).to be_nil
      expect(value.tooltip).to be_nil
      expect(value.label).to be_nil
      expect(value.blank).to be_nil
      expect(value.hide).to be(false)
    end

    it "keeps an html-safe buffer safe" do
      buffer = ActiveSupport::SafeBuffer.new("<b>XX11TEST</b>")
      wrapped = described_class.wrap(buffer)
      expect(wrapped.value).to eq(buffer)
      expect(wrapped.value).to be_html_safe
    end

    it "turns nil into a blank value" do
      expect(described_class.wrap(nil).value).to be_nil
      expect(described_class.wrap(nil)).to be_blank_value
    end

    it "reads a Hash as the keys it names" do
      wrapped = described_class.wrap(value: "XX11TEST", help: "Kommentar",
        tooltip: "Erklärung", label: "Eigenes Label", blank: :dash, hide: false)
      expect(wrapped.value).to eq("XX11TEST")
      expect(wrapped.help).to eq("Kommentar")
      expect(wrapped.tooltip).to eq("Erklärung")
      expect(wrapped.label).to eq("Eigenes Label")
      expect(wrapped.blank).to eq(:dash)
    end

    it "reads the hide-only Hash a raw formatter answers with" do
      expect(described_class.wrap(hide: true).hide).to be(true)
    end

    it "hands a DetailValue back unchanged" do
      value = described_class.new(value: "XX11TEST")
      expect(described_class.wrap(value)).to equal(value)
    end

    # The typo guard: {tooltop: "..."} must not silently vanish.
    it "raises for a key it does not know" do
      expect { described_class.wrap(tooltop: "Erklärung") }
        .to raise_error(ArgumentError, /tooltop/)
    end
  end

  describe "the blank mode" do
    it "accepts the four modes there are" do
      expect(described_class::BLANK_MODES).to eq(%i[hide dash empty unset])
      described_class::BLANK_MODES.each do |mode|
        expect(described_class.new(blank: mode).blank).to eq(mode)
      end
    end

    it "takes :unset from a Hash, like any other mode" do
      expect(described_class.wrap(value: nil, blank: :unset).blank).to eq(:unset)
    end

    it "accepts no blank mode at all (the field decides then)" do
      expect(described_class.new.blank).to be_nil
    end

    it "rejects a mode that is none of them" do
      expect { described_class.new(blank: :dashed) }
        .to raise_error(ArgumentError, /blank must be one of hide, dash, empty, unset/)
      expect { described_class.wrap(value: "x", blank: :dashed) }
        .to raise_error(ArgumentError, /blank must be one of/)
    end
  end

  describe "#blank_value?" do
    it "counts nil and the empty String as blank" do
      expect(described_class.new(value: nil)).to be_blank_value
      expect(described_class.new(value: "")).to be_blank_value
    end

    it "counts an empty list as blank" do
      expect(described_class.new(value: [])).to be_blank_value
    end

    # hitobito's attr_present? rule: a boolean field shows its "Nein".
    it "counts false as a value" do
      expect(described_class.new(value: false)).not_to be_blank_value
    end

    it "counts 0 and any text as a value" do
      expect(described_class.new(value: 0)).not_to be_blank_value
      expect(described_class.new(value: "XX11TEST")).not_to be_blank_value
    end
  end

  # Adding a key later must not break the formatters that return a String.
  it "compares by value, like every Data object" do
    expect(described_class.wrap("XX11TEST")).to eq(described_class.new(value: "XX11TEST"))
  end
end
