# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# A status change that starts or ends the contract is saved only after the
# question in the form is answered with yes (confirm_contract=1); the server
# decides whether to ask, on the stored contract.
describe Person::StatusController, type: :controller do
  render_views

  let(:manager) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }
  let(:person) { people(:yp_a_1) }

  before do
    WsjrdpPaymentPlan.kept.find_or_create_by!(wsjrdp_role: person.wsjrdp_role, single_payment: false,
      payment_method: "direct_debit") { |plan| plan.raw_installments_eur = [2026, 100, 100] }
    person.update_columns(status: "reviewed")
    sign_in(manager)
  end

  def put_status(status, confirm: nil, **attrs)
    put :update, params: {group_id: person.primary_group_id, id: person.id,
                          person: {status: status, **attrs}, confirm_contract: confirm}.compact
  end

  def question = Nokogiri::HTML(response.body).at_css("#contract-question")

  it "asks before the first confirmation and saves nothing, the form keeping its values" do
    put_status("confirmed", unit_code: "#ABCDEF")

    expect(response).to have_http_status(422)
    expect(question.text).to include("Vertrag bestätigen?", "bestätigt von #{manager}")
    expect(question.at_css("button[name='confirm_contract'][value='1']").text).to eq "Ja, Vertrag bestätigen"
    expect(Nokogiri::HTML(response.body).at_css("input[name='person[unit_code]']")["value"]).to eq "#ABCDEF"
    expect(person.reload).to have_attributes(status: "reviewed", contract_status: "none")
  end

  it "confirms the contract on yes, with the user as the confirming person" do
    put_status("confirmed", confirm: "1", unit_code: "#ABCDEF")

    expect(response).to redirect_to(status_person_path(person.id))
    expect(person.reload).to have_attributes(status: "confirmed", contract_status: "confirmed",
      contract_confirmed_by: manager, unit_code: "#ABCDEF")
  end

  it "asks before a new contract after the end, naming the end" do
    person.update_columns(contract_status: "ended", contract_confirmed_at: Time.zone.local(2025, 12, 16),
      contract_ended_at: Time.zone.local(2026, 2, 7), contract_confirmed_by_type: "Person",
      contract_confirmed_by_id: people(:admin).id)
    put_status("confirmed")

    expect(question.text).to include("Neuen Vertrag bestätigen?", "16.12.2025", "07.02.2026")
    put_status("confirmed", confirm: "1")
    expect(person.reload).to have_attributes(contract_status: "confirmed", contract_ended_at: nil,
      contract_confirmed_by: manager)
  end

  it "keeps the author of the contract in force through a deregistration" do
    person.update_columns(status: "confirmed", contract_status: "confirmed",
      contract_confirmed_at: Time.zone.local(2025, 12, 16), contract_confirmed_by_type: "Person",
      contract_confirmed_by_id: people(:admin).id)
    put_status("deregistered", confirm: "1")

    expect(person.reload).to have_attributes(contract_status: "ended", contract_confirmed_by: people(:admin))
  end

  it "records the impersonated person, the current user, as the author" do
    session[:origin_user] = people(:admin).id
    put_status("confirmed", confirm: "1")

    expect(person.reload.contract_confirmed_by).to eq manager
  end

  it "asks before the deregistration ends the contract in force" do
    person.update_columns(status: "confirmed", contract_status: "confirmed",
      contract_confirmed_at: Time.zone.local(2025, 12, 16))
    put_status("deregistered")

    expect(question.text).to include("Vertrag beenden?", "16.12.2025")
    expect(person.reload.contract_status).to eq "confirmed"
    put_status("deregistered", confirm: "1")
    expect(person.reload).to have_attributes(status: "deregistered", contract_status: "ended")
  end

  it "saves without asking what leaves the contract as it is" do
    person.update_columns(status: "upload", contract_status: "confirmed", contract_confirmed_at: 1.year.ago)
    put_status("confirmed")
    expect(response).to have_http_status(:redirect)

    person.update_columns(status: "reviewed", contract_status: "none", contract_confirmed_at: nil)
    put_status("deregistered")
    expect(response).to have_http_status(:redirect)
    put_status("deregistration_noted")
    expect(response).to have_http_status(:redirect)
    expect(person.reload).to have_attributes(status: "deregistration_noted", contract_status: "none")
  end
end
