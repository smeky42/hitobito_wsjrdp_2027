# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The mailings of a debit, from the data of their log entries.
describe Fin::WsjrdpDirectDebitPreNotificationsController do
  render_views

  let(:yp) { people(:yp_a_1) }
  let(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let(:order) do
    WsjrdpPaymentInitiation.create!(status: "planned", sepa_schema: "pain.008.001.08",
      message_identification: "MSG-1", number_of_transactions: 1, control_sum_cents: 40_000)
  end
  let(:debit) do
    WsjrdpDirectDebitPreNotification.create!(payment_initiation: order, subject: yp, author: yp,
      payment_status: "pre_notified", amount_cents: 40_000, collection_date: Date.new(2026, 11, 5),
      debit_sequence_type: "RCUR", description: "WSJ 2027 Rate", dbtr_name: "Erika Beispiel",
      dbtr_iban: "DE02120300000000202051", endtoend_id: "E2E-1")
  end

  def mailing(data)
    Wsjrdp::LogEntry.note!(debit, category: "pre_notification", message: "verschickt", main: yp,
      data: {"pre_notification_id" => debit.id}.merge(data))
  end

  it "keeps an address whole when its name has a comma, and shows malformed data" do
    mailing("email_to" => ["Beispiel, Erika <erika@example.org>"])
    mailing("email_status" => 5, "email_sent_at" => "gestern", "email_to" => [nil, 7, {}], "email_cc" => "a@example.org",
      "email_eml_size" => "x", "email_smtp_refused" => ["b"], "pre_notification_id" => "abc")
    sign_in(finance)

    get :show, params: {id: debit.id}

    expect(response).to be_successful
    expect(Capybara.string(response.body))
      .to have_link("Beispiel, Erika <erika@example.org>", href: "mailto:erika@example.org")
  end
end
