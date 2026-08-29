# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The expense sub-rows of a Moss reimbursement in the transactions list
# (Fin::MossExpenseRowsHelper): WHICH rows a transaction brings, the cap and
# the rest row's aggregation, and what each of the five filled cells shows.
#
# The transactions are BUILT here -- the helper reads the expenses and their
# bookings through the associations, so they are saved -- and every name,
# number and amount is invented.
describe Fin::MossExpenseRowsHelper do
  def fragment(html) = Nokogiri::HTML.fragment(html)

  # A reimbursement with one expense per entry. An entry names the expense's
  # amount, its words and the [Sachkonto, Kostenstelle] of each of its
  # bookings; the transaction total is their sum.
  def reimbursement(*entries)
    total = entries.sum { |entry| entry.fetch(:amount) }
    transaction = MossReimbursement.create!(moss_transaction_uuid: SecureRandom.uuid,
      currency: "EUR", signed_total_base_amount: total, payment_date: Date.new(2026, 5, 3))
    entries.each_with_index { |entry, index| expense(transaction, index + 1, **entry) }
    transaction.reload
  end

  # One expense of `transaction`, with one booking per [Sachkonto,
  # Kostenstelle] pair (its amount split evenly over them).
  def expense(transaction, number, amount:, name: "Ausgabe #{number}", text: nil,
    codes: [["66500", "2300"]])
    row = MossExpense.create!(moss_transaction: transaction, type: "#{transaction.type}Expense",
      moss_transaction_uuid: transaction.moss_transaction_uuid, expense_number: number,
      signed_expense_base_amount: amount, expense_name: name, expense_posting_text: text)
    codes.each_with_index do |(account, cost_center), index|
      MossBooking.create!(moss_transaction: transaction, moss_expense: row,
        moss_transaction_uuid: transaction.moss_transaction_uuid,
        booking_unique_item_number: "#{transaction.moss_transaction_uuid}_#{number}_#{index}",
        signed_base_amount: amount / codes.size, account_number: account,
        cost_center_number: cost_center)
    end
    row
  end

  # `count` expenses of the same shape, numbered from one.
  def entries(count, amount: -10)
    Array.new(count) { |index| {amount: amount, name: "Ausgabe #{index + 1}"} }
  end

  def sub_rows(transaction) = helper.moss_expense_sub_rows(transaction)

  def cell(sub, key) = fragment(helper.moss_expense_row_cell(sub, key))

  describe "which transactions bring sub-rows" do
    # 59 % of the reimbursements: the head row already carries that one
    # expense's amount, name and codes, so a second row would only repeat it.
    it "leaves a reimbursement with one expense a single row" do
      expect(sub_rows(reimbursement({amount: -40}))).to eq([])
    end

    it "gives a reimbursement with two expenses one row per expense" do
      rows = sub_rows(reimbursement({amount: -40}, {amount: -25}))
      expect(rows.map(&:kind)).to eq([:expense, :expense])
      expect(rows.map(&:ordinal)).to eq([1, 2])
      expect(rows.map(&:hidden)).to all(be false)
    end

    # The rows follow expense_number, not the order the expenses were written.
    it "orders the rows by expense_number" do
      transaction = reimbursement({amount: -40}, {amount: -25})
      transaction.expenses.first.update!(expense_number: 9)
      rows = sub_rows(transaction.reload)
      expect(rows.map { |row| row.expense.expense_number }).to eq([2, 9])
      expect(rows.map(&:ordinal)).to eq([1, 2])
    end

    # The other three kinds have no real middle level -- their one expense is a
    # shell around the transaction.
    it "gives a card payment, an invoice and a top-up none" do
      %w[MossCardTransaction MossInvoice MossTopUp].each do |type|
        transaction = MossTransaction.create!(type: type, currency: "EUR",
          moss_transaction_uuid: SecureRandom.uuid, signed_total_base_amount: -23.35)
        expense(transaction, 1, amount: -23.35)
        expect(sub_rows(transaction.reload)).to eq([])
      end
    end
  end

  describe "the cap" do
    it "shows all four expenses of a group of four and no rest row" do
      rows = sub_rows(reimbursement(*entries(4)))
      expect(rows.map(&:kind)).to eq([:expense] * 4)
      expect(rows.map(&:hidden)).to all(be false)
    end

    # The fifth expense IS rendered -- hidden, so its link reveals it without a
    # request.
    it "hides the fifth expense of a group of five behind the rest row" do
      rows = sub_rows(reimbursement(*entries(5)))
      expect(rows.map(&:kind)).to eq([:expense] * 5 + [:rest, :collapse])
      expect(rows.select(&:expense?).map(&:hidden)).to eq([false, false, false, false, true])
      expect(rows.find(&:rest?).count).to eq(1)
    end

    # The tallest case in the data: capped, it is exactly as tall as a group of
    # five.
    it "leaves a group of thirteen four rows and one rest row" do
      rows = sub_rows(reimbursement(*entries(13)))
      expect(rows.count { |row| row.expense? && !row.hidden }).to eq(4)
      expect(rows.count { |row| row.expense? && row.hidden }).to eq(9)
      expect(cell(rows.find(&:rest?), "description").text).to eq("▸ 9 weitere Ausgaben anzeigen")
    end

    it "sums the amounts, codes and bookings of the expenses behind the rest row" do
      rows = sub_rows(reimbursement(*entries(4),
        {amount: -30, name: "Ausgabe 5", codes: [["66630", "2500"], ["63040", "2100"]]},
        {amount: -20, name: "Ausgabe 6", codes: [["66630", "2500"]]}))
      rest = rows.find(&:rest?)
      expect(rest.amount).to eq(-50)
      expect(rest.count).to eq(2)
      expect(rest.bookings_count).to eq(3)
      expect(rest.account_numbers).to contain_exactly("66630", "63040")
      expect(rest.cost_center_numbers).to contain_exactly("2500", "2100")
      expect(cell(rest, "description").text).to eq("▸ 2 weitere Ausgaben anzeigen")
    end

    # One expense, two expenses: the German plural of the rest row's link.
    it "says 'weitere Ausgabe' about a single remaining expense" do
      rows = sub_rows(reimbursement(*entries(5)))
      expect(cell(rows.find(&:rest?), "description").text).to eq("▸ 1 weitere Ausgabe anzeigen")
    end
  end

  describe "the row classes" do
    it "names each kind of row" do
      rows = sub_rows(reimbursement(*entries(5)))
      classes = rows.map { |row| helper.moss_expense_row_class(row) }
      expect(classes.first(4)).to eq(["moss-expense-row"] * 4)
      expect(classes[4]).to eq("moss-expense-row moss-expense-extra d-none")
      expect(classes[5]).to eq("moss-expense-rest")
      expect(classes.last).to eq("moss-expense-collapse d-none")
    end

    it "hides the expenses beyond the cap" do
      rows = sub_rows(reimbursement(*entries(6)))
      expect(rows.select(&:hidden).map { |row| helper.moss_expense_row_class(row) })
        .to eq(["moss-expense-row moss-expense-extra d-none"] * 2)
    end
  end

  describe "the toggle links" do
    let(:rows) { sub_rows(reimbursement(*entries(6))) }

    it "reveals the hidden rows from the rest row" do
      link = cell(rows.find(&:rest?), "description").at_css("a")
      expect(link["href"]).to eq("#")
      expect(link["data-moss-expense-toggle"]).to eq("expand")
      expect(link["class"]).to eq("moss-expense-toggle")
      expect(link.text).to eq("▸ 2 weitere Ausgaben anzeigen")
    end

    it "folds them away again from the collapse row" do
      link = cell(rows.find(&:collapse?), "description").at_css("a")
      expect(link["data-moss-expense-toggle"]).to eq("collapse")
      expect(link.text).to eq("▴ einklappen")
    end

    # The collapse row stands for no expense: it shows a link and nothing else.
    it "leaves every other cell of the collapse row empty" do
      collapse = rows.find(&:collapse?)
      %w[signed_total_base_amount account_numbers cost_centers bookings_count].each do |key|
        expect(helper.moss_expense_row_cell(collapse, key)).to eq("")
      end
    end
  end

  describe "the description cell" do
    def description(**attrs)
      rows = sub_rows(reimbursement({amount: -40, **attrs}, {amount: -25}))
      cell(rows.first, "description")
    end

    it "puts the ordinal before the expense's name" do
      html = description(name: "Bahnfahrt Vortreffen")
      expect(html.at_css("span.moss-expense-desc")).to be_present
      expect(html.at_css("span.moss-expense-ordinal").text).to eq("1")
      expect(html.text).to eq("1Bahnfahrt Vortreffen")
    end

    it "adds the Buchungstext in italics after a dash" do
      html = description(name: "Bahnfahrt Vortreffen", text: "Hin- und Rückfahrt")
      expect(html.at_css("i").text).to eq("Hin- und Rückfahrt")
      expect(html.text).to eq("1Bahnfahrt Vortreffen – Hin- und Rückfahrt")
    end

    # The same dedupe rule as MossBooking#text_lines: a text that only repeats
    # the name says nothing.
    it "drops a text that equals the name" do
      html = description(name: "Kopierkosten", text: "Kopierkosten")
      expect(html.at_css("i")).to be_nil
      expect(html.text).to eq("1Kopierkosten")
    end

    it "shows the text alone when the expense has no name" do
      html = description(name: nil, text: "Verpflegung Samstag")
      expect(html.at_css("i").text).to eq("Verpflegung Samstag")
      expect(html.text).to eq("1Verpflegung Samstag")
    end

    it "shows the ordinal alone when the expense has neither" do
      expect(description(name: nil, text: nil).text).to eq("1")
    end

    # Name and Buchungstext are free text in Moss; a long one would wrap the
    # row over several lines, so the row shows at most
    # MOSS_EXPENSE_TEXT_MAX_LENGTH characters of them.
    it "leaves words that fit untouched, and gives them no title" do
      html = description(name: "Bahnfahrt Vortreffen", text: "Hin- und Rückfahrt")
      expect(html.at_css("span.moss-expense-desc")["title"]).to be_nil
      expect(html.text).to eq("1Bahnfahrt Vortreffen – Hin- und Rückfahrt")
    end

    it "cuts longer words to the maximum and keeps the whole string in the title" do
      text = (["Verpflegung und Getränke für das Vortreffen"] * 5).join(", ")
      html = description(name: "Bahnfahrt Vortreffen", text: text)
      desc = html.at_css("span.moss-expense-desc")
      shown = desc.text.delete_prefix("1")

      expect(shown.length).to be <= described_class::MOSS_EXPENSE_TEXT_MAX_LENGTH
      expect(shown).to end_with("…")
      expect(desc["title"]).to eq("Bahnfahrt Vortreffen – #{text}")
      # The name still fits, so what was cut is the text -- and it stays italic.
      expect(shown).to start_with("Bahnfahrt Vortreffen – ")
      expect(html.at_css("i").text).to end_with("…")
    end

    # Cut in the NAME: there is nothing of the text left to show, so the row
    # carries no italics at all.
    it "cuts a name longer than the maximum and drops the text behind it" do
      name = (["Sammelabrechnung Vortreffen Nordlicht"] * 5).join(", ")
      html = description(name: name, text: "Hin- und Rückfahrt")
      desc = html.at_css("span.moss-expense-desc")

      expect(desc.text.delete_prefix("1").length)
        .to be <= described_class::MOSS_EXPENSE_TEXT_MAX_LENGTH
      expect(html.at_css("i")).to be_nil
      expect(desc["title"]).to eq("#{name} – Hin- und Rückfahrt")
    end
  end

  describe "the amount cell" do
    def amount_span(amount)
      rows = sub_rows(reimbursement({amount: amount}, {amount: -25}))
      cell(rows.first, "signed_total_base_amount").at_css("span")
    end

    # The head row's format, muted: the column keeps reading as the
    # transactions' amounts while the group adds up below it.
    it "shows money going out muted, in the head row's format" do
      span = amount_span(-86.9)
      expect(span["class"]).to eq("moss-expense-amount text-muted")
      expect(span.text.squish).to eq("-86,90 €")
    end

    # As on the wallet: the sign is the cue, the green only reinforces it.
    it "shows money coming back in green, with a plus" do
      span = amount_span(34.9)
      expect(span["class"]).to eq("moss-expense-amount moss-amount-in")
      expect(span.text.squish).to eq("+34,90 €")
    end
  end

  describe "the code and count cells" do
    # An expense split across two accounts stays ONE row; that it is two shows
    # in its cells -- two Sachkonten, two Kostenstellen and the 2 in Buchungen.
    it "shows both bookings of a split expense in one row" do
      rows = sub_rows(reimbursement(
        {amount: -38.5, codes: [["66500", "2300"], ["63040", "2100"]]}, {amount: -25}
      ))
      expect(rows.size).to eq(2)
      split = rows.first
      expect(cell(split, "account_numbers").text).to eq("6304066500")
      expect(cell(split, "cost_centers").text).to eq("21002300")
      expect(helper.moss_expense_row_cell(split, "bookings_count")).to eq(2)
    end

    # The codes are the DISTINCT ones -- two bookings against one account are
    # one Sachkonto.
    it "names a repeated code once" do
      rows = sub_rows(reimbursement(
        {amount: -20, codes: [["66500", "2300"], ["66500", "2300"]]}, {amount: -25}
      ))
      expect(cell(rows.first, "account_numbers").text).to eq("66500")
      expect(helper.moss_expense_row_cell(rows.first, "bookings_count")).to eq(2)
    end

    # A known code is followed by its name, as in the head row.
    it "puts the account's name behind its number" do
      WsjrdpLedgerAccount.create!(number: "66500", name: "Verpflegung", account_kind: "EXPENSE")
      rows = sub_rows(reimbursement({amount: -20}, {amount: -25}))
      expect(cell(rows.first, "account_numbers").text).to eq("66500 Verpflegung")
    end
  end

  # Datum, Art, the person columns, the dates, the status, the invoice number,
  # the Original-Währung and DATEV: the cell is rendered and shows nothing.
  describe "the columns a sub-row does not fill" do
    let(:filled_keys) do
      %w[signed_total_base_amount description account_numbers cost_centers bookings_count]
    end

    it "renders every other column key as an empty cell" do
      rows = sub_rows(reimbursement(*entries(5)))
      (Fin::MossTransactionsColumns::COLUMNS.keys - filled_keys).each do |key|
        rows.each { |row| expect(helper.moss_expense_row_cell(row, key)).to eq("") }
      end
    end
  end
end
