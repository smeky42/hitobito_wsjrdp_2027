# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Person::FeeController do
  # A migrated database holds a payment plan per role, a schema-loaded one none.
  def ensure_payment_plan(person)
    WsjrdpPaymentPlan.find_or_create_by!(wsjrdp_role: person.wsjrdp_role, single_payment: false) do |plan|
      plan.raw_installments_eur = [2026, 100, 100]
    end
  end

  before_all(setup_fixtures: true) { ensure_payment_plan(people(:yp_a_1)) }

  let_it_be(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let(:yp) { people(:yp_a_1) }

  # Only the person themselves may edit a person who is in no layer.
  it "shows a person without any role in the root group" do
    person = Fabricate(:person)
    ensure_payment_plan(person)
    sign_in(person)

    get :show, params: {person_id: person.id}

    expect(response).to be_successful
    expect(assigns(:group)).to eq(Group.root)
  end

  it "uses the group of the URL" do
    sign_in(people(:admin))

    get :show, params: {group_id: groups(:ist_a).id, id: yp.id}

    expect(assigns(:group)).to eq(groups(:ist_a))
  end

  it "uses the primary group without a group in the URL" do
    sign_in(people(:admin))

    get :show, params: {person_id: yp.id}

    expect(assigns(:group)).to eq(yp.primary_group)
  end

  describe "the statement" do
    it "answers the PDF inline" do
      sign_in(people(:admin))

      get :statement, params: {person_id: yp.id}

      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to start_with("%PDF")
      expect(response.headers["Content-Disposition"]).to start_with("inline").and include("Beitragszahlungen")
    end

    it "is the person's own" do
      allow_any_instance_of(Wsjrdp2027::FeeStatement).to receive(:to_pdf).and_return("%PDF-1.4\n")
      sign_in(yp)

      get :statement, params: {person_id: yp.id}

      expect(response).to be_successful
    end

    it "is refused to a leader of another unit" do
      sign_in(people(:ul_b_1))

      expect { get :statement, params: {person_id: yp.id} }.to raise_error(CanCan::AccessDenied)
    end
  end

  describe "the page" do
    render_views

    let_it_be(:auditor) do
      Fabricate(Group::Extern::FinanceAuditor.name.to_sym,
        group: Group::Extern.create!(name: "Extern", parent: groups(:root))).person
    end

    before do
      yp.update_columns(sepa_name: "Erika Mustermann", sepa_iban: "DE02120300000000202051",
        sepa_bic: "BYLADEM1001", status: "printed", birthday: Date.new(2010, 5, 1), town: "Musterstadt",
        sepa_address: "Musterstraße 1", sepa_mandate_date: Date.new(2025, 9, 1))
      Wsj27RdpFeeRule.create!(people_id: yp.id, status: "deleted", activated_at: 3.days.ago, deleted_at: 1.day.ago,
        custom_installments_starting_year: 2026, custom_installments_cents: [0, 5_000],
        custom_installments_issue: "HELP-10", deleted_by: finance)
      active = Wsj27RdpFeeRule.create!(people_id: yp.id, status: "active", activated_at: 1.day.ago,
        custom_installments_starting_year: 2026, custom_installments_cents: [0, 10_000],
        custom_installments_issue: "HELP-11", custom_installments_comment: "Vereinbarung aktiv",
        custom_installments_payment_method: "credit_transfer", activated_by: finance)
      Wsj27RdpFeeRule.create!(people_id: yp.id, status: "planned",
        custom_installments_starting_year: 2026, custom_installments_cents: [0, 0, 7_000],
        custom_installments_issue: "HELP-12", custom_installments_comment: "Vereinbarung geplant")
      yp.update!(Wsjrdp2027::ParticipationFee.person_installments_attrs(active))
      yp.update!(wsjrdp_total_fee_reduction: 250, wsjrdp_total_fee_reduction_hint: "Härtefall",
        wsjrdp_total_fee_reduction_issue: "HELP-123", wsjrdp_total_fee_reduction_comment: "Nachweis liegt vor",
        planned_total_fee_reduction: "400", planned_total_fee_reduction_comment: "Erhöhung")
    end

    def page_as(viewer)
      sign_in(viewer)
      get :show, params: {person_id: yp.id}
      Nokogiri::HTML(response.body)
    end

    def bank_account(doc) = doc.at_css("section.bank-account")

    def installments(doc) = doc.at_css("section.installments")

    def fee_reduction(doc) = doc.at_css("section.fee-reduction")

    def expect_bank_account(doc)
      html = bank_account(doc)
      expect(html.text).to include("Erika Mustermann", "BYLADEM1001", yp.sepa_mandate_id)
      expect(html.text.delete(" ")).to include("DE02120300000000202051")
      expect(html.at_css("a.sepa-account-change[href^='mailto:finanzen@worldscoutjamboree.de?']")).to be_present
    end

    it "shows the person themselves the bank account, the Ratenplan without issues, plans, history or " \
       "buttons, and no Beitragshöhe" do
      doc = page_as(yp)

      aggregate_failures do
        expect_bank_account(doc)
        expect(installments(doc).text).not_to include("HELP-11", "HELP-12", "HELP-10", "Vereinbarung")
        expect(installments(doc).to_html).not_to include(edit_person_installments_path(yp))
        expect(fee_reduction(doc)).to be_nil
      end
    end

    it "shows the auditor the bank account" do
      expect_bank_account(page_as(auditor))
    end

    it "hides the Beitragshöhe from the unit leader" do
      expect(fee_reduction(page_as(people(:ul_a_1)))).to be_nil
    end

    it "shows a CMT leader the issues, plans and history, without comments or buttons" do
      doc = page_as(people(:cmt_leader))

      aggregate_failures do
        expect(installments(doc).text).to include("HELP-11", "HELP-12", "HELP-10")
        expect(installments(doc).text).not_to include("Vereinbarung")
        expect(installments(doc).to_html).not_to include(edit_person_installments_path(yp))
        expect(fee_reduction(doc).text).to include("Härtefall", "HELP-123", "Geplant: Reduktion 400")
        expect(fee_reduction(doc).text).not_to include("Nachweis liegt vor", "Erhöhung")
        expect(fee_reduction(doc).to_html)
          .not_to include(activate_person_fee_reduction_path(yp), edit_person_fee_reduction_path(yp))
      end
    end

    it "shows finance the SEPA mandate, the comments, the buttons and the anchors, on a page that morphs" do
      doc = page_as(finance)

      aggregate_failures do
        expect(bank_account(doc).at_css("a[href='#{mandate_person_bank_account_path(yp)}']")).to be_present
        expect(bank_account(doc).at_css(".sepa-mandate-missing")).to be_nil
        expect(installments(doc).text).to include("Vereinbarung aktiv", "Vereinbarung geplant")
        expect(installments(doc).to_html).to include(activate_person_installments_path(yp, context: "person"),
          ERB::Util.html_escape(edit_person_installments_path(yp, mode: "edit", context: "person")))
        expect(doc.at_css("section#payment_plan_#{yp.id}.installments")).to be_present
        expect(doc.at_css("section#total_fee_#{yp.id}.fee-reduction")).to be_present
        expect(response.body).to include(edit_person_debit_return_path(yp))
        expect(fee_reduction(doc).text).to include("Nachweis liegt vor", "Erhöhung")
        expect(fee_reduction(doc).to_html)
          .to include(activate_person_fee_reduction_path(yp), discard_person_fee_reduction_path(yp))
        expect(response.body.index("Ratenplan")).to be < response.body.index("Beitragshöhe")
        expect(response.body).to include('<meta name="turbo-refresh-method" content="morph">',
          '<meta name="turbo-refresh-scroll" content="preserve">')
      end
    end

    it "disables the SEPA mandate for finance and names what is missing" do
      yp.update_columns(birthday: nil, town: nil, sepa_mandate_date: nil)

      html = bank_account(page_as(finance))

      expect(html.at_css("a[href='#{mandate_person_bank_account_path(yp)}']")).to be_nil
      expect(html.at_css(".sepa-mandate-missing").text).to include(Person.human_attribute_name(:birthday),
        Person.human_attribute_name(:town), Person.human_attribute_name(:sepa_mandate_date))
    end

    it "lists the changes of the active reduction only, never the comment" do
      yp.update!(planned_total_fee_reduction: nil)
      with_versioning do
        yp.update!(wsjrdp_total_fee_reduction: 300, wsjrdp_total_fee_reduction_comment: "Neu vereinbart")
        yp.update!(wsjrdp_total_fee_reduction_comment: "Nur der Kommentar")
        yp.update!(nickname: "Anderswo")
      end

      html = fee_reduction(page_as(finance))

      expect(html.text).to include("250€ → 300€")
      expect(html.text).not_to include("Neu vereinbart", "Anderswo")
    end
  end
end
