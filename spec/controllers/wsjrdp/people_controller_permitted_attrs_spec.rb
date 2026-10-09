# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The person's edit form (PeopleController#update) changes neither status,
# sepa_status nor wsj_role -- the status page and the finance actions do,
# with their own permissions -- and the payment choice and the account only
# while the person is registered, as the form offers them, or for finance.
describe PeopleController, type: :controller do
  let(:yp) { people(:yp_a_1) }
  let(:unit_leader) { people(:ul_a_1) }
  let(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  let(:guarded) do
    {status: "deregistered", sepa_status: "individual_ok", wsj_role: "CMT"}
  end
  let(:payment) do
    {early_payer: "true", sepa_name: "Neu", sepa_address: "Neue Straße 1", sepa_mail: "neu@example.com",
     sepa_iban: "DE02120300000000202051", sepa_bic: "BYLADEM1001"}
  end

  def put_person(target, **attrs)
    put :update, params: {group_id: target.primary_group_id, id: target.id, person: attrs}
  end

  def snapshot(person) = person.reload.attributes.slice(*%w[status sepa_status wsj_role early_payer
    sepa_name sepa_address sepa_mail sepa_iban sepa_bic nickname])

  before do
    [yp, people(:ul_a_2)].each do |person|
      person.update_columns(status: "confirmed", sepa_status: "ok", wsj_role: nil, early_payer: false,
        sepa_name: "Alt", sepa_address: "Alte Straße 1", sepa_mail: "alt@example.com",
        sepa_iban: "DE89370400440532013000", sepa_bic: "COBADEFFXXX")
    end
  end

  {
    "the person themselves" => [:yp_a_1, :yp_a_1],
    "a unit leader, for a participant of the unit" => [:ul_a_1, :yp_a_1],
    "a unit leader, for another leader of the unit" => [:ul_a_1, :ul_a_2]
  }.each do |who, (actor, target)|
    it "keeps status, sepa_status, wsj_role and, after the registration, the payment fields from #{who}" do
      target = people(target)
      before = snapshot(target)
      sign_in(people(actor))

      put_person(target, nickname: "Spitzname", **guarded, **payment)

      expect(snapshot(target)).to eq before.merge("nickname" => "Spitzname")
    end
  end

  it "takes the payment fields while the person is registered, never status, sepa_status or wsj_role" do
    yp.update_columns(status: "registered")
    sign_in(yp)

    put_person(yp, **guarded, **payment)

    expect(yp.reload).to have_attributes(status: "registered", sepa_status: "ok", wsj_role: nil,
      early_payer: true, sepa_name: "Neu", sepa_iban: "DE02120300000000202051")
  end

  it "takes the payment fields from finance after the registration too, never status, sepa_status or wsj_role" do
    sign_in(finance)

    put_person(yp, **guarded, **payment)

    expect(yp.reload).to have_attributes(status: "confirmed", sepa_status: "ok", wsj_role: nil,
      early_payer: true, sepa_name: "Neu")
  end
end
