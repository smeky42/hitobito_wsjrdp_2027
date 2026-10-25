# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# "SEPA" on the person's page: "Einmalzahlung?", then the fields
# people/_sepa_account_attrs shares with "Kontoverbindung" on the Beitrag page.
describe PeopleController, type: :controller do
  render_views

  let(:yp) { people(:yp_a_1) }

  before do
    yp.update_columns(sepa_name: "Erika Mustermann", sepa_iban: "DE02120300000000202051", sepa_bic: "BYLADEM1001")
    sign_in(people(:admin))
  end

  it "shows the bank account under SEPA" do
    yp.update_columns(print_at: Date.new(2025, 9, 1))
    get :show, params: {group_id: yp.primary_group_id, id: yp.id}

    html = Capybara.string(response.body)
    expect(html).to have_css("h2", text: I18n.t("people.form_tabs.finance"))
    expect(html).to have_css("dt", text: "Einmalzahlung?")
    expect(html).to have_text("Erika Mustermann").and have_text("BYLADEM1001")
      .and have_text(yp.sepa_mandate_id)
    expect(html).to have_css("dt", text: "Mandatsdatum")
    expect(html).to have_css("dd", text: "01.09.2025")
  end

  # The mail's body, decoded from the link on the page.
  def mail_query
    href = Capybara.string(response.body).find("a.sepa-account-change")[:href]
    address, query_string = href.delete_prefix("mailto:").split("?", 2)
    query = query_string.split("&").to_h { |pair| pair.split("=", 2).map { |part| CGI.unescape(part.gsub("+", "%2B")) } }
    query.merge("address" => address)
  end

  it "offers a mail to the finance team to change the bank account" do
    get :show, params: {group_id: yp.primary_group_id, id: yp.id}

    query = mail_query
    expect(query["address"]).to eq("finanzen@worldscoutjamboree.de")
    expect(query["subject"]).to eq("Änderung Kontoverbindung #{yp.role_id_name}")
    expect(query["body"]).to include("DE02120300000000202051")
    expect(query["body"]).not_to include("Einzug zum")
  end

  it "names an announced collection by date, amount and purpose" do
    order = WsjrdpPaymentInitiation.create!(status: "planned", sepa_schema: "pain.008.001.08",
      message_identification: "MSG-1", number_of_transactions: 1, control_sum_cents: 30_000)
    WsjrdpDirectDebitPreNotification.create!(payment_initiation: order, subject: yp, author: yp,
      payment_status: "pre_notified", amount_cents: 30_000, collection_date: Date.new(2026, 11, 5),
      debit_sequence_type: "RCUR", description: "WSJ 2027 6. Rate November 2026", dbtr_name: "Muster",
      dbtr_iban: "DE02120300000000202051", endtoend_id: "E2E-1")

    get :show, params: {group_id: yp.primary_group_id, id: yp.id}

    expect(mail_query["body"]).to include("05.11.2026").and include("300,00 €")
      .and include("WSJ 2027 6. Rate November 2026")
  end

  it "offers the participant's address and mail in the SEPA fields of the edit form" do
    yp.update_columns(status: "registered", street: "Musterstraße", housenumber: "1", zip_code: "12345",
      town: "Musterstadt", email: "erika@example.org")

    get :edit, params: {group_id: yp.primary_group_id, id: yp.id}

    html = Capybara.string(response.body)
    expect(html).to have_css("button[data-copy-from-participant='address'][data-copy-target='#person_sepa_address']" \
      "[data-copy-value='Musterstraße 1, 12345 Musterstadt']")
    expect(html).to have_css("button[data-copy-from-participant='email'][data-copy-value='erika@example.org']")
  end
end
