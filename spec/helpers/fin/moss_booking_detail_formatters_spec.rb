# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The fields of a Moss booking's own page. The records are built, not saved.
# All names, numbers and amounts are invented.
describe Fin::MossBookingsHelper do
  let(:wallet) { WsjrdpFinAccount.new(id: 5, short_name: "Moss-Wallet") }

  let(:transaction) do
    MossReimbursement.new(id: 746, moss_transaction_uuid: SecureRandom.uuid, fin_account: wallet,
      signed_total_base_amount: -60, currency: "EUR", booking_date: Date.new(2026, 6, 1),
      transaction_name: "Fahrtkosten Vortreffen")
  end

  let(:booking) do
    expense = MossReimbursementExpense.new(moss_transaction: transaction, expense_number: 1,
      signed_expense_base_amount: -60)
    MossBooking.new(id: 9, moss_transaction: transaction, moss_expense: expense, sub_row_number: 1,
      signed_base_amount: -60, booking_posting_text: "Erstattung Vortreffen")
  end

  let(:transaction_path) { "/fin/moss/transactions/746" }

  def fragment(html) = Nokogiri::HTML.fragment(html.to_s)

  def links(html) = fragment(html).css("a").map { |a| [a.text.strip, a["href"], a["target"]] }

  before { allow(helper).to receive(:can?).and_return(true) }

  it "shows the amount with two decimals" do
    expect(fragment(helper.fin_format_moss_booking_amount_with_currency(booking)).text).to start_with("-60,00")
  end

  it "links the account twice: here and in a new tab" do
    expect(links(helper.fin_format_moss_booking_fin_account(booking)).map { |_, href, target| [href, target] })
      .to eq([["/fin/acc/5", nil], ["/fin/acc/5", "_blank"]])
  end

  it "marks a value of the transaction as coming from it, and leaves a missing one out" do
    aggregate_failures do
      expect(helper.moss_booking_transaction_value(booking, :booking_date))
        .to include(value: "01.06.2026", help: "aus der Transaktion")
      expect(helper.moss_booking_transaction_value(booking, :submitted_date)).to be_nil
    end
  end

  describe "the transaction line" do
    def line = helper.moss_booking_transaction_line(booking)

    it "links the transaction as \"#<id>\" twice, then its text, without a repeated amount" do
      transaction.transaction_posting_text = "Fahrt Vortreffen"

      aggregate_failures do
        expect(links(line)).to eq([["#746", transaction_path, nil], ["", transaction_path, "_blank"]])
        expect(fragment(line).text.squish).to eq("#746 Fahrt Vortreffen")
      end
    end

    it "adds the transaction's amount where it differs from the booking's" do
      transaction.signed_total_base_amount = -150
      expect(fragment(line).text.squish).to include("(-150,00")
    end

    it "shows the transaction as text without :show on it" do
      allow(helper).to receive(:can?).with(:show, transaction).and_return(false)

      aggregate_failures do
        expect(links(line)).to be_empty
        expect(fragment(line).text).to include("#746")
      end
    end
  end

  it "links the payment in Moss twice, on a line of its own" do
    transaction.moss_reimbursement_uuid = SecureRandom.uuid
    moss_line = fragment(helper.fin_format_moss_booking_moss_transaction(booking)).css("div")
      .find { |div| div.text.strip == "in Moss öffnen" }

    expect(moss_line.css("a").pluck("target")).to eq([nil, "_blank"])
  end

  it "lists the booking's own Buchungstext even where it repeats the text above" do
    transaction.transaction_name = booking.booking_posting_text

    expect(helper.moss_booking_page_text_lines(booking).last).to eq([:booking, nil, "Erstattung Vortreffen"])
  end
end
