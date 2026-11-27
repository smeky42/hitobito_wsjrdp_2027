# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The person side of one Moss booking, with the buttons that link a person
# and create their Beitragsbuchung.
describe "fin/moss_bookings/_subject_links" do
  before_all(setup_fixtures: true) do
    @finance = Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person
    tx = MossTransaction.create!(type: "MossInvoice", moss_transaction_uuid: SecureRandom.uuid,
      signed_total_base_amount: -100, currency: "EUR", booking_date: Date.new(2026, 5, 6))
    expense = MossExpense.create!(moss_transaction: tx, moss_expense_uuid: SecureRandom.uuid,
      type: "MossInvoiceExpense", expense_number: 1, signed_expense_base_amount: -100)
    @booking = MossBooking.create!(moss_transaction: tx, moss_expense: expense, sub_row_number: 1,
      signed_base_amount: -100, account_number: "66500", account_kind: "EXPENSE",
      booking_posting_text: "Rechnung CMT #{people(:cmt_leader).id}")
  end

  let(:finance) { @finance }
  let(:target) { people(:cmt_leader) }
  let(:booking) { MossBooking.find(@booking.id) }
  let(:ability) { Ability.new(finance) }

  before do
    without_partial_double_verification do
      allow(view).to receive(:can?) { |*args| ability.can?(*args) }
      allow(view).to receive(:current_user).and_return(finance)
    end
  end

  def entry_for(person, booking_date: Date.new(2026, 5, 6), **links)
    AccountingEntry.create!(subject: person, author: person, amount_cents: -10_000,
      description: "Beitrag", value_date: booking_date, booking_date: booking_date, **links)
  end

  def hrefs = Capybara.string(rendered).all("a").pluck(:href)

  def render_block = render(partial: "fin/moss_bookings/subject_links", locals: {booking: booking})

  it "offers creating the Beitragsbuchung in one step first, then linking and declining" do
    render_block

    expect(hrefs).to eq([
      "/fin/moss/bookings/#{booking.id}/link_subject_and_create_accounting_entry/#{target.id}/Person",
      "/fin/moss/bookings/#{booking.id}/link_subject/#{target.id}/Person",
      "/fin/moss/bookings/#{booking.id}/disallow_link_subject/#{target.id}/Person"
    ])
  end

  it "names an existing matching Beitragsbuchung instead of the create button" do
    existing = entry_for(target)

    render_block

    expect(rendered).to include("##{existing.id}")
    expect(hrefs.grep(/link_subject_and_create_accounting_entry/)).to be_empty
    expect(hrefs.grep(%r{/link_subject/})).to be_present
  end

  it "offers no create button without :create on AccountingEntry" do
    allow(ability).to receive(:can?).and_call_original
    allow(ability).to receive(:can?).with(:create, AccountingEntry).and_return(false)

    render_block

    expect(hrefs.grep(/link_subject_and_create_accounting_entry/)).to be_empty
    expect(hrefs.grep(%r{/link_subject/})).to be_present
  end

  it "offers one link button per unlinked Beitragsbuchung of the linked person's amount" do
    booking.update!(contribution_subject: target)
    first = entry_for(target)
    second = entry_for(target, booking_date: Date.new(2025, 1, 10))
    entry_for(target, moss_booking: MossBooking.create!(moss_transaction: booking.moss_transaction,
      moss_expense: booking.moss_expense, sub_row_number: 2, signed_base_amount: -100))

    render_block

    expect(hrefs.grep(%r{/link_accounting_entry/})).to contain_exactly(
      "/fin/moss/bookings/#{booking.id}/link_accounting_entry/#{first.id}",
      "/fin/moss/bookings/#{booking.id}/link_accounting_entry/#{second.id}"
    )
  end

  it "offers no button read-only" do
    booking.update!(contribution_subject: target)

    render partial: "fin/moss_bookings/subject_links", locals: {booking: booking, actions: false}

    expect(Capybara.string(rendered)).to have_no_css("a[data-turbo-method]")
  end
end
