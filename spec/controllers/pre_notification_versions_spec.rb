# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Changes to a pre-notification: in the person's log, in its row on the
# Beitrag page and on its detail pages.
describe "pre-notification changes", versioning: true do
  before_all(setup_fixtures: true) {}

  let(:yp) { people(:yp_a_1) }
  let(:admin) { people(:admin) }

  let_it_be(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let_it_be(:debit, refind: true) do
    order = WsjrdpPaymentInitiation.create!(status: "planned", sepa_schema: "pain.008.001.08",
      message_identification: "MSG-1", number_of_transactions: 1, control_sum_cents: 40_000)
    PaperTrail.enabled = true
    debit = PaperTrail.request(enabled: true) do
      WsjrdpDirectDebitPreNotification.create!(payment_initiation: order, subject: people(:yp_a_1),
        author: people(:yp_a_1), payment_status: "pre_notified", amount_cents: 40_000,
        collection_date: Date.new(2026, 11, 5), debit_sequence_type: "RCUR", description: "WSJ 2027 Rate",
        dbtr_name: "Alt Name", dbtr_iban: "DE02120300000000202051", endtoend_id: "E2E-1")
    end
    PaperTrail.request(enabled: true, whodunnit: people(:admin).id.to_s) { debit.update!(dbtr_name: "Neu Name") }
    debit
  ensure
    PaperTrail.enabled = false
  end

  def html = Capybara.string(response.body)

  it "keeps the change under the person, a debit without one under nobody" do
    expect(debit.versions.last).to have_attributes(event: "update", main_id: yp.id, main_type: Person.sti_name)

    debit.update_columns(subject_type: "Group", subject_id: groups(:root).id)
    debit.reload.update!(dbtr_name: "Ohne Person")
    expect(debit.versions.last).to have_attributes(main_id: nil, main_type: nil)
  end

  describe Person::LogController, type: :controller do
    render_views

    let(:log_params) { {group_id: yp.primary_group_id, id: yp.id} }

    it "shows it in the person's log, naming the debit by its id unlinked and amounts as euros" do
      PaperTrail.request(whodunnit: admin.id.to_s) { debit.update!(amount_cents: 45_000) }
      sign_in(admin)

      get :index, params: log_params

      aggregate_failures do
        expect(html).to have_text("Alt Name").and have_text("Neu Name")
        expect(html).to have_text("Vorabankündigung ##{debit.id}: ").and have_no_text("wurde aktualisiert")
        expect(html).to have_no_link("##{debit.id}")
        expect(html).to have_text("400,00€").and have_text("450,00€")
        expect(html).to have_no_text("45000")
      end
    end

    it "links the debit for whoever may open it" do
      sign_in(finance)

      get :index, params: log_params

      expect(html).to have_css("a[href='#{wsjrdp_direct_debit_pre_notification_path(debit)}'][target='_blank']", text: "##{debit.id}")
    end
  end

  describe Person::FeeController, type: :controller do
    render_views

    before do
      WsjrdpPaymentPlan.find_or_create_by!(wsjrdp_role: yp.wsjrdp_role, single_payment: false) do |plan|
        plan.raw_installments_eur = [2026, 100, 100]
      end
    end

    it "shows it in the debit's row on the Beitrag page" do
      sign_in(admin)

      get :show, params: {person_id: yp.id}

      change = html.find(".debit-change")
      expect(change).to have_text("Alt Name → Neu Name")
      expect(change).to have_css("span[title='#{admin}']")
    end

    it "leaves it out of the person's own Beitrag page" do
      sign_in(yp)

      get :show, params: {person_id: yp.id}

      expect(html).to have_no_css(".debit-change")
    end
  end

  describe Fin::WsjrdpDirectDebitPreNotificationsController, type: :controller do
    render_views

    # people(:admin) is a Root::Leader; an Admin holds the finance tiers.
    [Group::Root::Finance, Group::Root::Admin].each do |role|
      it "shows it on the debit's page under the person, for #{role.name.demodulize}" do
        sign_in(Fabricate(role.name.to_sym, group: groups(:root)).person)

        get :show, params: {id: debit.id}

        expect(html.find(".debit-change")).to have_text("Alt Name").and have_text("Neu Name")
      end
    end
  end
end
