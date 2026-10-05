# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Moss link of a Beitragsbuchung in its edit form (finance manage only): the
# number of the Moss booking, "Verknüpfung lösen", the stored link as the
# field's help, and the provenance written for a change. Values are invented.
describe Fin::AccountingEntriesController, type: :controller do
  render_views

  let(:manager) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }
  let(:person) { people(:yp_a_1) }

  def moss_booking(text)
    uuid = SecureRandom.uuid
    transaction = MossTransaction.create!(type: "MossInvoice", moss_transaction_uuid: uuid,
      signed_total_base_amount: -100, currency: "EUR", booking_date: Date.new(2026, 3, 2))
    expense = MossExpense.create!(moss_transaction: transaction, moss_expense_uuid: uuid,
      type: "MossInvoiceExpense", expense_number: 1, signed_expense_base_amount: -100)
    MossBooking.create!(moss_transaction: transaction, moss_expense: expense, sub_row_number: 1,
      signed_base_amount: -100, booking_posting_text: text)
  end

  let!(:linked) { moss_booking("Rechnung eins") }
  let!(:other) { moss_booking("Rechnung zwei") }

  let!(:entry) do
    AccountingEntry.create!(subject: person, author: manager, amount_cents: -10_000,
      description: "Rechnung", value_date: Date.new(2026, 3, 2), booking_date: Date.new(2026, 3, 2),
      moss_booking: linked,
      moss_booking_link_meta: {"created_at" => "2026-03-05T10:00:00+01:00", "author_id" => manager.id,
                               "automatic_manual" => "manual"})
  end

  before do
    sign_in(manager)
    session[:max_finance_permission] = "finance_manage"
  end

  def doc = Nokogiri::HTML(response.body)

  def field = doc.at_css("input[name='accounting_entry[moss_booking_id]']")

  describe "GET show" do
    it "offers the number field and the unlink box, with the stored link as help" do
      get :show, params: {id: entry.id}

      expect(field["value"]).to eq linked.id.to_s
      expect(doc.at_css("input[type=checkbox][name='unlink_moss_booking']")).to be_present
      help = field.ancestors(".row, .mb-2").first.text.squish
      expect(help).to include("Bisher:").and include("[#{linked.id}]").and include("Rechnung")
      expect(help).to include("verknüpft am 05.03.2026").and include("(manuell)")
    end

    it "only shows the link below the manage tier" do
      session[:max_finance_permission] = "finance"
      get :show, params: {id: entry.id}

      expect(field).to be_nil
      expect(doc.text).to include("[#{linked.id}]")
    end
  end

  describe "PUT update" do
    # `unlink:` is the plain request param "Verknüpfung lösen" (not an entry attribute).
    def update(unlink: nil, **attrs)
      put(:update, params: {id: entry.id, accounting_entry: attrs, unlink_moss_booking: unlink}.compact)
    end

    it "moves the link to another Moss booking and records it as a manual link" do
      update(moss_booking_id: other.id.to_s)

      entry.reload
      expect(entry.moss_booking_id).to eq other.id
      expect(entry.moss_booking_link_meta).to include("author_id" => manager.id, "automatic_manual" => "manual")
      expect(entry.moss_booking_link_meta["created_at"]).to be_present
    end

    it "removes the link with the unlink box, whatever the number field says" do
      update(moss_booking_id: linked.id.to_s, unlink: "1")

      entry.reload
      expect(entry.moss_booking_id).to be_nil
      expect(entry.moss_booking_link_meta).to eq({})
    end

    it "removes the link with an empty number field" do
      update(moss_booking_id: "")

      expect(entry.reload.moss_booking_id).to be_nil
    end

    it "leaves link and provenance alone when the number is unchanged" do
      update(moss_booking_id: linked.id.to_s, unlink: "0", comment: "geprüft")

      entry.reload
      expect(entry.moss_booking_id).to eq linked.id
      expect(entry.moss_booking_link_meta["created_at"]).to eq "2026-03-05T10:00:00+01:00"
      expect(entry.comment).to eq "geprüft"
    end

    it "refuses an unknown number and keeps the stored link in the help" do
      update(moss_booking_id: "999999999")

      expect(response).to have_http_status(400)
      expect(doc.text).to include("Moss-Buchung #999999999 gibt es nicht")
      expect(doc.text).not_to include("Moss-Buchung Moss-Buchung")
      expect(field.ancestors(".row, .mb-2").first.text).to include("[#{linked.id}]")
      expect(entry.reload.moss_booking_id).to eq linked.id
    end

    it "ignores the link below the manage tier" do
      session[:max_finance_permission] = "finance"
      update(moss_booking_id: other.id.to_s, unlink: "1", comment: "geprüft")

      entry.reload
      expect(entry.moss_booking_id).to eq linked.id
      expect(entry.comment).to eq "geprüft"
    end
  end
end
