# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The formatter lookup of the finance detail partials: which helper a field
# reaches, what it may return, and what happens to a field that has none.
#
# The records here are unsaved and every value is invented -- names, IBANs and
# amounts in this spec mean nothing.
describe Fin::AttrFormatHelper do
  let(:ctx) { Fin::AttrFormatContext.regular }

  let(:account) do
    WsjrdpPersonalAccount.new(number: "700000", name: "Testkreditor",
      iban: "XX11TEST0000", datev_short_name: "TESTKRED")
  end

  # Defines a formatter on the view context under test -- exactly what a
  # <model>_helper.rb of the wagon does, only for one example.
  def stub_helper(name, &block)
    helper.singleton_class.define_method(name, &block)
  end

  describe "the candidate helper names" do
    # The core rule (base class) plus the STI subclass in front of it, plus the
    # model-wide name for fields several models share.
    it "asks the STI subclass before the base class before the attribute" do
      expect(helper.fin_formatter_names(MossTopUp.new, :display_name)).to eq(
        %i[fin_format_moss_top_up_display_name
          fin_format_moss_transaction_display_name
          fin_format_display_name]
      )
    end

    it "names a model without STI subclasses once" do
      expect(helper.fin_formatter_names(account, :iban))
        .to eq(%i[fin_format_wsjrdp_personal_account_iban fin_format_iban])
    end
  end

  describe "the lookup" do
    it "takes the STI subclass's formatter when there is one" do
      stub_helper(:fin_format_moss_top_up_display_name) { |_obj| "Top-up" }
      stub_helper(:fin_format_moss_transaction_display_name) { |_obj| "Transaktion" }
      stub_helper(:fin_format_display_name) { |_obj| "Irgendwas" }
      expect(helper.fin_format_attr(MossTopUp.new, :display_name, ctx).value).to eq("Top-up")
    end

    it "falls back to the base class's formatter" do
      stub_helper(:fin_format_moss_transaction_display_name) { |_obj| "Transaktion" }
      stub_helper(:fin_format_display_name) { |_obj| "Irgendwas" }
      expect(helper.fin_format_attr(MossTopUp.new, :display_name, ctx).value).to eq("Transaktion")
    end

    it "falls back to the model-wide formatter of the attribute" do
      stub_helper(:fin_format_display_name) { |_obj| "Irgendwas" }
      expect(helper.fin_format_attr(MossTopUp.new, :display_name, ctx).value).to eq("Irgendwas")
    end

    it "hands a one-liner the object alone" do
      stub_helper(:fin_format_wsjrdp_personal_account_iban) { |obj| obj.iban.downcase }
      expect(helper.fin_format_attr(account, :iban, ctx).value).to eq("xx11test0000")
    end

    it "hands a two-argument formatter the context as well" do
      stub_helper(:fin_format_wsjrdp_personal_account_iban) do |obj, context|
        context.embedded? ? "gekürzt" : obj.iban
      end
      expect(helper.fin_format_attr(account, :iban, ctx).value).to eq("XX11TEST0000")
      embedded = Fin::AttrFormatContext.embedded(Wsjrdp::TableContext.new(level: 1, lazy: true))
      expect(helper.fin_format_attr(account, :iban, embedded).value).to eq("gekürzt")
    end

    it "normalises a Hash result into the DetailValue keys" do
      stub_helper(:fin_format_wsjrdp_personal_account_iban) do |obj|
        {value: obj.iban, help: "Wie in Moss hinterlegt", blank: :dash}
      end
      detail = helper.fin_format_attr(account, :iban, ctx)
      expect(detail.value).to eq("XX11TEST0000")
      expect(detail.help).to eq("Wie in Moss hinterlegt")
      expect(detail.blank).to eq(:dash)
    end

    # nil from a FIELD formatter is a blank value, not "use the default".
    it "reads nil from a formatter as a blank value" do
      stub_helper(:fin_format_wsjrdp_personal_account_iban) { |_obj| nil }
      expect(helper.fin_format_attr(account, :iban, ctx)).to be_blank_value
    end
  end

  describe "the type rules" do
    def value_of(attr, record = account) = helper.fin_format_attr(record, attr, ctx).value

    it "writes a date in the finance notation" do
      account.define_singleton_method(:valid_from) { Date.new(2026, 3, 4) }
      expect(value_of(:valid_from)).to eq("04.03.2026")
    end

    it "writes a timestamp with the time of day" do
      account.updated_at = Time.zone.local(2026, 3, 4, 15, 30)
      expect(value_of(:updated_at)).to eq("04.03.2026 15:30")
    end

    it "joins an array, dropping its blanks" do
      account.aliases = ["Alias Eins", "", "Alias Zwei"]
      expect(value_of(:aliases)).to eq("Alias Eins, Alias Zwei")
    end

    it "reads an empty array as a blank value" do
      account.aliases = []
      expect(helper.fin_format_attr(account, :aliases, ctx)).to be_blank_value
    end

    it "formats a *_cents column as money" do
      account.define_singleton_method(:open_amount_cents) { 12_345 }
      expect(value_of(:open_amount_cents)).to eq("123,45#{Fin::MoneyHelper::NBSP}€")
    end

    it "formats a *_amount decimal as money" do
      account.define_singleton_method(:base_amount) { BigDecimal("12.5") }
      expect(value_of(:base_amount)).to eq("12,50#{Fin::MoneyHelper::NBSP}€")
    end

    # A jsonb column belongs into a raw block, where the keys keep their names.
    it "refuses a jsonb column" do
      account.other_datev_columns = {"Adressattyp" => "2"}
      expect { value_of(:other_datev_columns) }
        .to raise_error(ArgumentError, /jsonb column, list it in d.raw_entries/)
    end
  end

  describe "the blank rule" do
    # hitobito's chain answers a nil with a non-breaking space, which would put
    # an invisible "value" into every empty field.
    it "reads a nil column as a blank value, not as a space" do
      detail = helper.fin_format_attr(account, :bic, ctx)
      expect(detail.value).to be_nil
      expect(detail).to be_blank_value
    end

    it "reads an empty string as a blank value" do
      expect(helper.fin_format_attr(account, :description, ctx)).to be_blank_value
    end

    it "reads false as a value" do
      account.define_singleton_method(:sepa_mandate) { false }
      detail = helper.fin_format_attr(account, :sepa_mandate, ctx)
      expect(detail).not_to be_blank_value
      expect(detail.value).to eq(I18n.t("global.no"))
    end
  end

  describe "the fallback into hitobito's chain" do
    it "formats a boolean the way every hitobito page does" do
      account.define_singleton_method(:sepa_mandate) { true }
      expect(helper.fin_format_attr(account, :sepa_mandate, ctx).value)
        .to eq(I18n.t("global.yes"))
    end

    it "formats a plain string column" do
      expect(helper.fin_format_attr(account, :name, ctx).value).to eq("Testkreditor")
    end
  end

  describe "#fin_attr_visible?" do
    # The seam of plan §3.5 -- until the declaration mechanism is decided, every
    # field is visible.
    it "shows every field for now" do
      expect(helper.fin_attr_visible?(account, :iban, ctx)).to be(true)
      expect(helper.fin_attr_visible?(account, :other_datev_columns, ctx)).to be(true)
    end
  end

  describe "#fin_raw_format" do
    let(:raw_ctx) { ctx.with_raw_source(:other_datev_columns) }

    before do
      # Keys the model's own raw helper (Fin::PersonalAccountsHelper) does not
      # claim, so these examples see the kit's default formatting.
      account.other_datev_columns = {"Kurzbezeichnung" => "TESTKRED", "Zahlungsträger" => "1",
                                     "Gesperrt" => false, "Konditionen" => {"Tage" => 14}}
    end

    it "writes an entry as stored when no helper answers" do
      expect(helper.fin_raw_format(account, "Kurzbezeichnung", raw_ctx).value).to eq("TESTKRED")
    end

    it "writes a boolean as the word the export wrote" do
      expect(helper.fin_raw_format(account, "Gesperrt", raw_ctx).value).to eq("false")
    end

    it "writes nested JSON compact, on one line" do
      expect(helper.fin_raw_format(account, "Konditionen", raw_ctx).value)
        .to eq('{"Tage":14}')
    end

    # A jsonb column stores its dates as text; a date reaches a raw block
    # through an also: column, and keeps the finance notation there.
    it "writes a date in the finance notation" do
      account.define_singleton_method(:valid_from) { Date.new(2026, 3, 4) }
      expect(helper.fin_raw_format(account, :valid_from, ctx).value).to eq("04.03.2026")
    end

    it "reads an also: column off the record itself" do
      expect(helper.fin_raw_format(account, :datev_short_name, ctx).value).to eq("TESTKRED")
    end

    it "takes what the model's raw helper says" do
      stub_helper(:fin_raw_format_other_wsjrdp_personal_account) do |obj, key, context|
        if [context.raw_source, key] == [:other_datev_columns, "Kurzbezeichnung"]
          "#{obj.other_datev_columns[key]} (gekürzt)"
        end
      end
      expect(helper.fin_raw_format(account, "Kurzbezeichnung", raw_ctx).value)
        .to eq("TESTKRED (gekürzt)")
    end

    # nil from a RAW helper means "nothing special", not "blank".
    it "falls back to the default when the raw helper answers nil" do
      stub_helper(:fin_raw_format_other_wsjrdp_personal_account) { |_obj, _key, _context| nil }
      expect(helper.fin_raw_format(account, "Zahlungsträger", raw_ctx).value).to eq("1")
    end

    it "lets the raw helper drop an entry with hide" do
      stub_helper(:fin_raw_format_other_wsjrdp_personal_account) do |_obj, key, _context|
        {hide: true} if key == "Zahlungsträger"
      end
      expect(helper.fin_raw_format(account, "Zahlungsträger", raw_ctx).hide).to be(true)
      expect(helper.fin_raw_format(account, "Kurzbezeichnung", raw_ctx).hide).to be(false)
    end

    it "tells the two jsonb columns apart by the raw source" do
      account.other_moss_columns = {"Kurzbezeichnung" => "Moss-Wert"}
      moss_ctx = ctx.with_raw_source(:other_moss_columns)
      expect(helper.fin_raw_format(account, "Kurzbezeichnung", moss_ctx).value).to eq("Moss-Wert")
      expect(helper.fin_raw_format(account, "Kurzbezeichnung", raw_ctx).value).to eq("TESTKRED")
    end

    it "asks the STI subclass's raw helper first" do
      expect(helper.fin_raw_formatter_names(MossTopUp.new))
        .to eq(%i[fin_raw_format_other_moss_top_up fin_raw_format_other_moss_transaction])
    end
  end
end
