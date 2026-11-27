# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The pre-notification a mailing's log entry names.
describe PaperTrail::VersionDecorator, :draper_with_helpers do
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

  def changes(viewer, pre_notification_id: debit.id)
    version = Wsjrdp::LogEntry.note!(debit, category: "pre_notification", message: "verschickt", main: yp,
      data: {"pre_notification_id" => pre_notification_id})
    decorator = described_class.new(version)
    allow(decorator.h).to receive(:can?) { |action, record| Ability.new(viewer).can?(action, record) }
    Capybara.string(decorator.changes)
  end

  it "links the pre-notification only for who may open it" do
    link = {href: Rails.application.routes.url_helpers.wsjrdp_direct_debit_pre_notification_path(debit)}

    expect(changes(finance)).to have_link("##{debit.id}", **link)
    expect(changes(people(:admin))).to have_text("##{debit.id}").and have_no_link("##{debit.id}")
  end

  it "names a pre-notification that is gone without a link" do
    id = debit.id
    debit.delete

    expect(changes(finance, pre_notification_id: id)).to have_text("##{id}").and have_no_link
  end

  it "shows an id it cannot read as stored" do
    expect(changes(finance, pre_notification_id: "abc")).to have_text("abc")
  end
end
