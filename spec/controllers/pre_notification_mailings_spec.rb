# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe "pre-notification mailings", type: :request do
  let(:yp) { people(:yp_a_1) }
  let(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let(:order) do
    WsjrdpPaymentInitiation.create!(status: "planned", sepa_schema: "pain.008.001.08",
      message_identification: "MSG-1", number_of_transactions: 1, control_sum_cents: 40_000)
  end
  let!(:debit) do
    WsjrdpDirectDebitPreNotification.create!(payment_initiation: order, subject: yp, author: yp,
      payment_status: "pre_notified", amount_cents: 40_000, collection_date: Date.new(2026, 11, 5),
      debit_sequence_type: "RCUR", description: "WSJ 2027 Rate", dbtr_name: "Erika Beispiel",
      dbtr_iban: "DE02120300000000202051", endtoend_id: "E2E-1")
  end

  def html = Capybara.string(response.body)

  def mailing(data = {})
    Wsjrdp::LogEntry.note!(debit, category: "pre_notification", message: "verschickt", main: yp,
      data: {"pre_notification_id" => debit.id}.merge(data))
  end

  it "links the pre-notification in the log only for who may open it" do
    mailing

    sign_in(people(:admin))
    get log_group_person_path(yp.primary_group_id, yp.id)
    expect(html).to have_text("##{debit.id}")
    expect(html).to have_no_link("##{debit.id}")

    sign_in(finance)
    get log_group_person_path(yp.primary_group_id, yp.id)
    expect(html).to have_link("##{debit.id}", href: wsjrdp_direct_debit_pre_notification_path(debit))

    debit.delete
    get log_group_person_path(yp.primary_group_id, yp.id)
    expect(html).to have_no_link("##{debit.id}")
  end

  it "keeps an address whole when its name has a comma" do
    mailing("email_to" => ["Beispiel, Erika <erika@example.org>"])
    sign_in(finance)

    get wsjrdp_direct_debit_pre_notification_path(debit)

    expect(html).to have_link("Beispiel, Erika <erika@example.org>", href: "mailto:erika@example.org")
  end

  it "does not fail on malformed data" do
    mailing
    mailing("email_status" => 5, "email_sent_at" => "gestern", "email_to" => [nil, 7, {}], "email_cc" => "a@example.org",
      "email_eml_size" => "x", "email_smtp_refused" => ["b"], "pre_notification_id" => "abc")
    sign_in(finance)

    get wsjrdp_direct_debit_pre_notification_path(debit)
    expect(html).to have_css(".debit-mailing", count: 2)

    get log_group_person_path(yp.primary_group_id, yp.id)
    expect(response).to be_successful
  end
end
