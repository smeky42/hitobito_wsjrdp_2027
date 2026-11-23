# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# A Moss expense's reading page, its row detail and its edit page
# (Fin::MossExpensesController). All names and amounts are invented.
describe Fin::MossExpensesController do
  render_views

  let(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  let(:transaction) do
    MossTransaction.create!(type: "MossReimbursement", moss_transaction_uuid: SecureRandom.uuid,
      signed_total_base_amount: -60, currency: "EUR", booking_date: Date.new(2026, 6, 1),
      transaction_name: "Fahrtkosten Vortreffen")
  end

  let!(:expense) do
    MossExpense.create!(moss_transaction: transaction, moss_expense_uuid: SecureRandom.uuid,
      type: "MossReimbursementExpense", expense_number: 1, signed_expense_base_amount: -60,
      expense_name: "Bahnfahrt", expense_posting_text: "Anreise")
  end

  let!(:booking) do
    MossBooking.create!(moss_transaction: transaction, moss_expense: expense, sub_row_number: 1,
      signed_base_amount: -60, booking_posting_text: "Anreise")
  end

  before { sign_in(person) }

  def page = Nokogiri::HTML(response.body)

  it "renders the field list with Bearbeiten and the transaction, without inputs" do
    get :show, params: {id: expense.id}

    expect(page.at_css("#main h1").text).to include("Moss Ausgabe ##{expense.id}").and include("Bahnfahrt")
    expect(page.at_css("#main h1 a[href='#{edit_moss_expense_path(expense)}']")).to be_present
    expect(page.at_css("#main a[href='#{moss_transaction_path(transaction)}']")).to be_present
    expect(page.css("#main textarea[name='moss_expense[comment]']")).to be_empty
  end

  # The bookings stand as a table below, each row loading the booking's detail.
  it "lists the expense's bookings as an expandable table" do
    get :show, params: {id: expense.id}

    expect(response.body).to include("Buchungen (1)")
    frame = page.at_css("turbo-frame[data-record='moss_booking_#{booking.id}']")
    expect(frame["src"]).to start_with(moss_booking_path(booking))
    expect(page.at_css("#bkframe-meb-#{booking.id}")).to be_present
  end

  it "lists the bookings as links in a row's detail" do
    request.headers["Turbo-Frame"] = "bkframe-mte-#{expense.id}"
    get :show, params: {id: expense.id, expandable_table_level: 1}

    expect(page.at_css("a[href='#{moss_booking_path(booking)}']").text).to eq "##{booking.id}"
    expect(page.css("table")).to be_empty
  end

  it "gives a row's detail the inline edit form" do
    request.headers["Turbo-Frame"] = "bkframe-mte-#{expense.id}"
    get :show, params: {id: expense.id, expandable_table_level: 1}

    frame = page.at_css("turbo-frame#bkframe-mte-#{expense.id}")
    expect(frame.at_css("h1")).to be_nil
    expect(frame.at_css("textarea[name='moss_expense[comment]']")).to be_present
  end

  it "shows the comment as an input on the edit page and saves it" do
    get :edit, params: {id: expense.id}
    expect(page.at_css("form[action='#{moss_expense_path(expense)}'] textarea[name='moss_expense[comment]']"))
      .to be_present

    patch :update, params: {id: expense.id, moss_expense: {comment: "Geprüft"}}
    expect(response).to redirect_to(moss_expense_path(expense))
    expect(expense.reload.comment).to eq "Geprüft"
  end

  # A failed save shows the same form again: the edit page, or the row's detail
  # for a save from a row (Fin::DetailPages#save_detail).
  it "shows the form again when the save fails" do
    allow_any_instance_of(MossExpense).to receive(:save).and_return(false)

    patch :update, params: {id: expense.id, moss_expense: {comment: "x"}}
    expect(response).to have_http_status(422)
    expect(response).to render_template(:edit)

    request.headers["Turbo-Frame"] = "bkframe-mte-#{expense.id}"
    patch :update, params: {id: expense.id, moss_expense: {comment: "x"}}
    expect(response).to have_http_status(422)
    expect(response).to render_template(:show)
  end

  it "stays on the edit page with 'Speichern und weiter'" do
    patch :update, params: {id: expense.id, stay: "1", return_url: "/fin/moss", moss_expense: {comment: "x"}}

    expect(response).to redirect_to(edit_moss_expense_path(expense, return_url: "/fin/moss"))
  end

  it "closes the edit page to the read tier" do
    sign_in(Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person)

    expect { get :edit, params: {id: expense.id} }.to raise_error(CanCan::AccessDenied)
  end
end
