# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The kind's visual vocabulary as the views get it: the CHIP (wallet rows, the
# booking detail header) and the html_safe TAB LABELS the Moss sheet declares by
# symbol. Icon and colour class come from Fin::MossKinds, every WORD from the
# locale -- so this spec reads the locale rather than repeating German text.
# Plus the date cells of the listing, whose dates are invented.
describe Fin::MossTransactionsHelper do
  def chip(type) = Nokogiri::HTML.fragment(helper.moss_kind_chip(type)).at_css("span.moss-kind")

  # The four kind tabs of Sheet::Fin::Moss and the kind each one stands for.
  let(:tab_labels) do
    {"MossCardTransaction" => :moss_card_transactions_tab_label,
     "MossReimbursement" => :moss_reimbursements_tab_label,
     "MossInvoice" => :moss_invoices_tab_label,
     "MossTopUp" => :moss_top_ups_tab_label}
  end

  # The three date columns of the listing, each showing its own raw column --
  # and the one of them that writes its own em dash.
  describe "the date cells" do
    def cell(tx, key) = helper.moss_transaction_cell(tx, key)

    it "shows every date column's own column" do
      tx = MossCardTransaction.new(payment_date: Date.new(2026, 5, 3),
        booking_date: Date.new(2026, 5, 6), approval_date: Date.new(2026, 5, 4))
      expect(cell(tx, "booking_date")).to eq("06.05.2026")
      expect(cell(tx, "payment_date")).to eq("03.05.2026")
      expect(cell(tx, "approval_date")).to eq("04.05.2026")
    end

    # Two of the four kinds carry no payout day at all, so Zahlungsdatum says
    # that instead of rendering a blank cell.
    it "writes the em dash where the row has no payment date" do
      tx = MossReimbursement.new(booking_date: Date.new(2026, 6, 15))
      expect(cell(tx, "payment_date")).to eq("—")
      expect(cell(tx, "booking_date")).to eq("15.06.2026")
    end

    # The widget renders the blank cell from the nil.
    it "stays empty where the other date columns are empty" do
      tx = MossInvoice.new
      expect(cell(tx, "booking_date")).to be_nil
      expect(cell(tx, "approval_date")).to be_nil
    end
  end

  Fin::MossKinds::STYLE.each_key do |kind|
    describe "the #{kind} chip" do
      subject(:span) { chip(kind) }

      it "carries the kind's colour class and nothing else" do
        expect(span["class"].split).to contain_exactly("moss-kind", Fin::MossKinds.css_class(kind))
      end

      # The one-sentence explanation of the kind; without it the chip would be
      # four short words the reader has to guess the difference between.
      it "explains the kind in its tooltip" do
        expect(span["title"]).to be_present
        expect(span["title"]).to eq(I18n.t("fin.moss.kind_hints.#{kind}"))
        expect(helper.moss_kind_hint(kind)).to eq(span["title"])
      end

      # Icon AND word, always: colour is never the only cue (WCAG 1.4.1), and an
      # icon alone would be a riddle in a monochrome print-out.
      it "shows the kind's icon next to its short word" do
        icon = span.at_css("i")
        expect(icon["class"]).to eq("fas fa-#{Fin::MossKinds.icon(kind)}")
        expect(icon["aria-hidden"]).to eq("true")
        expect(span.text.strip).to eq(I18n.t("fin.moss.kind_chips.#{kind}"))
      end

      # The chip abbreviates ("Karte"); the tabs and tiles keep the long word.
      it "abbreviates where the kinds' own words are longer" do
        expect(helper.moss_kind_chip_label(kind)).to eq(I18n.t("fin.moss.kind_chips.#{kind}"))
        expect(helper.moss_kind_css_class(kind)).to eq(Fin::MossKinds.css_class(kind))
        expect(Nokogiri::HTML.fragment(helper.moss_kind_icon(kind)).at_css("i")["class"])
          .to eq("fas fa-#{Fin::MossKinds.icon(kind)}")
      end
    end
  end

  # A sheet tab may declare its label as a SYMBOL; the core then calls the
  # helper method of that name WITH THE SHEET ENTRY as its only argument and
  # renders the html_safe result inside the link (Sheet::Tab::Renderer#label).
  describe "the kind tab labels" do
    it "renders each one as the tab's own word behind the kind's icon" do
      tab_labels.each do |kind, method|
        label = helper.public_send(method, nil)
        expect(label).to be_html_safe
        fragment = Nokogiri::HTML.fragment(label)
        expect(fragment.text.strip).to eq(I18n.t("fin.tabs.#{Fin::MossKinds.slug(kind).pluralize}"))
        expect(fragment.text.strip).to eq(helper.moss_kind_tab_label(kind))
        expect(fragment.at_css("i")["class"]).to eq("fas fa-#{Fin::MossKinds.icon(kind)}")
        expect(fragment.at_css("i")["aria-hidden"]).to eq("true")
      end
    end

    # The method NAME is derived from the kind's slug, the sheet writes it out:
    # a drifting slug must be a loud NoMethodError on the tab, not a silently
    # missing label.
    it "provides every symbol label the Moss sheet declares" do
      symbols = Sheet::Fin::Moss.tabs.map(&:label_key).grep(Symbol)
      expect(symbols).to include(*tab_labels.values)
      expect(symbols).to all(satisfy { |sym| helper.respond_to?(sym) })
    end
  end
end
